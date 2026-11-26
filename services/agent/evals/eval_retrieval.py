"""Retrieval evaluation for clinic knowledge (AGENTS.md section 14.1): recall@1, recall@3 and mean reciprocal rank on
the meaning ranking, and how well the relevance gate refuses questions no document answers, for a range of floors.
Embeds the knowledge/ passages and the golden questions with bge-m3 on a local Ollama; no database needed (the hybrid
SQL is tested in supabase/tests/34_knowledge.test.sql).

    OLLAMA_URL=http://127.0.0.1:11434 uv run python evals/eval_retrieval.py
"""
import math
from pathlib import Path

import yaml

from agent import knowledge

ROOT = Path(__file__).parents[3]


def cosine(a, b):
    return sum(x * y for x, y in zip(a, b)) / (math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b)))


def main():
    golden = yaml.safe_load((Path(__file__).parent / "retrieval.yaml").read_text())
    passages = []
    for path in sorted(p for p in (ROOT / "knowledge").glob("*.md") if p.name != "README.md"):
        meta, parts = knowledge.parse(path)
        passages += [(path.stem, f"{meta['title']}. {h}. {c}") for h, c in parts]
    emb = knowledge._embedder()
    vectors = emb.embed_documents([t for _, t in passages])

    def ranked(q):
        v = emb.embed_query(q)
        return sorted(((cosine(v, pv), slug) for (slug, _), pv in zip(passages, vectors)), reverse=True)

    hits1 = hits3 = rr = 0
    best_answerable = []
    for item in golden["answerable"]:
        r = ranked(item["q"])
        docs = list(dict.fromkeys(slug for _, slug in r))          # rank of documents, best passage first
        rank = docs.index(item["doc"]) + 1
        hits1 += rank == 1; hits3 += rank <= 3; rr += 1 / rank
        best_answerable.append(r[0][0])
        if rank > 1:
            print(f"  miss [{item['lang']}] {item['q']!r}: got {docs[0]}, wanted {item['doc']} (rank {rank})")
    n = len(golden["answerable"])
    best_nothing = [ranked(item["q"])[0][0] for item in golden["nothing"]]
    print(f"recall@1 {hits1 / n:.2f}  recall@3 {hits3 / n:.2f}  MRR {rr / n:.2f}  (n={n})")
    print(f"best similarity, answerable: min {min(best_answerable):.3f}  median {sorted(best_answerable)[n // 2]:.3f}")
    print(f"best similarity, must find nothing: max {max(best_nothing):.3f}")
    for floor in (0.45, 0.50, 0.55, 0.60):
        kept = sum(s >= floor for s in best_answerable) / n
        refused = sum(s < floor for s in best_nothing) / len(best_nothing)
        print(f"floor {floor:.2f}: answerable kept {kept:.2f}, out-of-scope refused {refused:.2f}")
    limits = yaml.safe_load((Path(__file__).parent / "thresholds.yaml").read_text())["retrieval"]
    scores = {"recall_at_1": hits1 / n, "recall_at_3": hits3 / n, "mrr": rr / n,
              "out_of_scope_refused": sum(s < knowledge.SIMILARITY_FLOOR for s in best_nothing) / len(best_nothing)}
    failed = [k for k, v in scores.items() if v < limits[k]]
    print("PASS" if not failed else f"FAIL: {', '.join(failed)} below threshold")
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
