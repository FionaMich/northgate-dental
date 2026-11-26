-- Section 09: clinic knowledge that Nora can search (hybrid RAG in Postgres; docs/sections/09-knowledge-and-mcp.md).
-- Line-by-line review (Fiona): assistant safety (what Nora reads).
--
-- Approved clinic documents, split into passages, each with a keyword index (full-text search) and a meaning index
-- (pgvector, 1024 dimensions from bge-m3). No patient data. Signed-in users may search; only the service key writes,
-- through the ingestion command. One function fuses the two rankings by reciprocal rank fusion.

create extension if not exists vector with schema extensions;

create table public.knowledge_documents (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique check (slug ~ '^[a-z0-9-]{2,60}$'),
  title       text not null check (char_length(title) between 2 and 120),
  version     text not null check (char_length(version) between 1 and 20),
  reviewed_by text,
  reviewed_on date,
  checksum    text not null,
  updated_at  timestamptz not null default now()
);

create table public.knowledge_passages (
  id          uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.knowledge_documents (id) on delete cascade,
  ordinal     integer not null check (ordinal > 0),
  heading     text,
  content     text not null check (char_length(content) between 1 and 2000),
  tsv         tsvector generated always as (to_tsvector('english', coalesce(heading, '') || ' ' || content)) stored,
  embedding   extensions.vector(1024),
  unique (document_id, ordinal)
);
create index knowledge_passages_tsv on public.knowledge_passages using gin (tsv);
create index knowledge_passages_embedding on public.knowledge_passages
  using hnsw (embedding extensions.vector_cosine_ops);

alter table public.knowledge_documents enable row level security;
alter table public.knowledge_passages enable row level security;
create policy staff_need_mfa on public.knowledge_documents as restrictive for all to authenticated
  using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()));
create policy staff_need_mfa on public.knowledge_passages as restrictive for all to authenticated
  using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()));
create trigger audit_row after insert or update or delete on public.knowledge_documents
  for each row execute function private.audit_row();
create trigger audit_row after insert or update or delete on public.knowledge_passages
  for each row execute function private.audit_row();
revoke all on public.knowledge_documents, public.knowledge_passages from anon, authenticated;
grant select on public.knowledge_documents, public.knowledge_passages to authenticated;
create policy signed_in_reads_knowledge on public.knowledge_documents for select to authenticated using (true);
create policy signed_in_reads_passages on public.knowledge_passages for select to authenticated using (true);

-- The best passages for a question: rank by keywords and by meaning separately, then add 1 / (60 + rank) from each
-- ranking (reciprocal rank fusion, k = 60). Returns the vector similarity and whether the keywords matched, so the
-- caller can refuse weak matches (the relevance gate). query_embedding may be null: keywords only.
create function public.search_knowledge(query text, query_embedding extensions.vector(1024), match_count integer default 5)
returns table (passage_id uuid, document_title text, heading text, content text, similarity real, keyword_match boolean,
               score double precision)
language sql stable security invoker set search_path = '' as $$
  with q as (select websearch_to_tsquery('english', coalesce(query, '')) as tsq),
  by_words as (
    select p.id, row_number() over (order by ts_rank_cd(p.tsv, q.tsq) desc) as r
    from public.knowledge_passages p, q
    where p.tsv @@ q.tsq
    order by r limit 20),
  by_meaning as (
    select p.id, row_number() over (order by p.embedding operator(extensions.<=>) query_embedding) as r
    from public.knowledge_passages p
    where query_embedding is not null and p.embedding is not null
    order by p.embedding operator(extensions.<=>) query_embedding limit 20),
  fused as (
    select coalesce(w.id, m.id) as id, w.id is not null as keyword_match,
           coalesce(1.0 / (60 + w.r), 0) + coalesce(1.0 / (60 + m.r), 0) as score
    from by_words w full join by_meaning m on m.id = w.id)
  select p.id, d.title, p.heading, p.content,
         case when query_embedding is null or p.embedding is null then null
              else (1 - (p.embedding operator(extensions.<=>) query_embedding))::real end,
         f.keyword_match, f.score
  from fused f
  join public.knowledge_passages p on p.id = f.id
  join public.knowledge_documents d on d.id = p.document_id
  order by f.score desc
  limit least(greatest(match_count, 1), 10);
$$;
revoke all on function public.search_knowledge(text, extensions.vector, integer) from public;
grant execute on function public.search_knowledge(text, extensions.vector, integer) to authenticated;
