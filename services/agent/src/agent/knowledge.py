"""Clinic knowledge for Nora (section 09, docs/sections/09-knowledge-and-mcp.md): approved documents in knowledge/,
split at their headings, embedded with bge-m3 on the same Ollama as Gemma, and stored in Postgres for hybrid search.

    python -m agent.knowledge ingest [folder]   # needs SUPABASE_URL, SUPABASE_SECRET_KEY and OLLAMA_URL
    python -m agent.knowledge sql [folder] | psql "$DB_URL"   # the same upserts as SQL (the deploy workflow)

Ingestion is idempotent: an unchanged document (same checksum) is skipped; a changed one replaces its passages."""

import hashlib
import json
import os
import re
import sys
from pathlib import Path

import httpx
import yaml

EMBED_MODEL = os.environ.get("EMBED_MODEL", "bge-m3")
MAX_PASSAGE = 900
# The relevance gate: a passage reaches Nora only when its meaning is this close to the question (cosine similarity
# with bge-m3), or, when the embedder is down, when the keywords matched. Calibrated on evals/retrieval.yaml
# (2026-11-26): answerable questions scored 0.563 at the lowest, out-of-scope ones 0.448 at the highest; 0.50 sits
# between them with a margin on both sides.
SIMILARITY_FLOOR = float(os.environ.get("KNOWLEDGE_SIMILARITY_FLOOR", "0.50"))
NOTHING_FOUND = "No approved clinic document answers this. Offer to pass the question to the team."

# Text aimed at a model, not at a patient: a document carrying it is refused at ingestion.
_INSTRUCTIONS = re.compile(r"ignore (all |any |the )?(previous|prior|above|earlier) (instructions|rules)|system prompt|"
                           r"you are now|disregard (your|the|all) (rules|instructions)|act as (an?|the) ", re.I)


class UnsafeDocument(ValueError):
    pass


def parse(path: Path) -> tuple[dict, list[tuple[str, str]]]:
    """A document's front matter and its passages: (heading, text) per `##` section, long sections split at blank
    lines so that no passage is longer than MAX_PASSAGE characters."""
    text = path.read_text(encoding="utf-8")
    _, front, body = text.split("---", 2)
    meta = yaml.safe_load(front)
    passages = []
    for block in re.split(r"^## ", body, flags=re.M)[1:]:
        heading, _, content = block.partition("\n")
        part = ""
        for para in [p.strip() for p in content.strip().split("\n\n") if p.strip()]:
            if part and len(part) + len(para) + 2 > MAX_PASSAGE:
                passages.append((heading.strip(), part))
                part = ""
            part = f"{part}\n\n{para}".strip()
        if part:
            passages.append((heading.strip(), part[:MAX_PASSAGE]))
    for heading, content in passages:
        if _INSTRUCTIONS.search(f"{heading} {content}"):
            raise UnsafeDocument(f"{path.name}: '{heading}' contains instructions aimed at a model")
    return meta, passages


def _embedder():
    from langchain_ollama import OllamaEmbeddings
    return OllamaEmbeddings(model=EMBED_MODEL, base_url=os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434"))


def embed_query(question: str) -> list[float]:
    """The only model input for a search: the question as Nora wrote it for the tool (call card knowledge-embedding)."""
    return _embedder().embed_query(question)


def as_vector(values: list[float] | None) -> str | None:
    return None if values is None else "[" + ",".join(f"{v:.6g}" for v in values) + "]"


def relevant(rows: list[dict]) -> list[dict]:
    """The relevance gate (corrective RAG without a model grader): keep passages close enough in meaning, or, when
    there is no similarity because the embedder was down, passages whose keywords all matched."""
    return [r for r in rows if (r.get("similarity") is not None and r["similarity"] >= SIMILARITY_FLOOR)
            or (r.get("similarity") is None and r.get("keyword_match"))]


def ingest(folder: Path, url: str, key: str) -> dict:
    headers = {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    done = {"skipped": 0, "updated": 0, "passages": 0}
    embedder = _embedder()
    with httpx.Client(base_url=f"{url}/rest/v1", headers=headers, timeout=60) as db:
        for path in sorted(p for p in folder.glob("*.md") if p.name != "README.md"):
            meta, passages = parse(path)
            slug, checksum = path.stem, hashlib.sha256(path.read_bytes()).hexdigest()
            old = db.get("/knowledge_documents", params={"slug": f"eq.{slug}", "select": "id,checksum"}).json()
            if old and old[0]["checksum"] == checksum:
                done["skipped"] += 1
                continue
            doc = db.post("/knowledge_documents", params={"on_conflict": "slug"},
                          headers={"Prefer": "resolution=merge-duplicates,return=representation"},
                          json={"slug": slug, "title": meta["title"], "version": str(meta["version"]),
                                "reviewed_by": meta.get("reviewed_by"), "reviewed_on": str(meta.get("reviewed_on") or "") or None,
                                "checksum": checksum})
            doc.raise_for_status()
            doc_id = doc.json()[0]["id"]
            db.delete("/knowledge_passages", params={"document_id": f"eq.{doc_id}"}).raise_for_status()
            vectors = embedder.embed_documents([f"{meta['title']}. {h}. {c}" for h, c in passages])
            db.post("/knowledge_passages", json=[
                {"document_id": doc_id, "ordinal": i, "heading": h, "content": c, "embedding": as_vector(v)}
                for i, ((h, c), v) in enumerate(zip(passages, vectors), start=1)]).raise_for_status()
            done["updated"] += 1
            done["passages"] += len(passages)
    return done


def _literal(value) -> str:
    return "null" if value is None else "'" + str(value).replace("'", "''") + "'"


def to_sql(folder: Path, embedder=None) -> str:
    """Every document as one statement: upsert the document by slug, replace its passages. Run in one transaction."""
    embedder = embedder or _embedder()
    statements = []
    for path in sorted(p for p in folder.glob("*.md") if p.name != "README.md"):
        meta, passages = parse(path)
        vectors = embedder.embed_documents([f"{meta['title']}. {h}. {c}" for h, c in passages])
        rows = ",\n".join(f"((select id from d), {i}, {_literal(h)}, {_literal(c)}, {_literal(as_vector(v))}::extensions.vector)"
                          for i, ((h, c), v) in enumerate(zip(passages, vectors), start=1))
        statements.append(
            "with d as (insert into public.knowledge_documents (slug, title, version, reviewed_by, reviewed_on, checksum)\n"
            f"values ({_literal(path.stem)}, {_literal(meta['title'])}, {_literal(meta['version'])}, "
            f"{_literal(meta.get('reviewed_by'))}, {_literal(meta.get('reviewed_on'))}::date, "
            f"{_literal(hashlib.sha256(path.read_bytes()).hexdigest())})\n"
            "on conflict (slug) do update set title = excluded.title, version = excluded.version,\n"
            "  reviewed_by = excluded.reviewed_by, reviewed_on = excluded.reviewed_on, checksum = excluded.checksum, updated_at = now()\n"
            "returning id), gone as (delete from public.knowledge_passages where document_id = (select id from d))\n"
            f"insert into public.knowledge_passages (document_id, ordinal, heading, content, embedding) values\n{rows};")
    return "begin;\n" + "\n".join(statements) + "\ncommit;\n"


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("ingest", "sql"):
        sys.exit("usage: python -m agent.knowledge ingest|sql [folder]")
    folder = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).parents[4] / "knowledge"
    if sys.argv[1] == "sql":
        print(to_sql(folder))
    else:
        print(json.dumps(ingest(folder, os.environ["SUPABASE_URL"].rstrip("/"), os.environ["SUPABASE_SECRET_KEY"])))
