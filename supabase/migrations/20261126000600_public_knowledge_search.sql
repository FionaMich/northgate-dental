-- Section 09: the dental-tools MCP server searches the approved clinic documents without a session.
-- Line-by-line review (Fiona): row level security (a third function for signed-out callers).
--
-- The documents are public clinic information, the same text the website shows. Visitors still have no privilege on
-- the knowledge tables themselves (supabase/tests/00); this function returns passages and their titles only, the
-- same result as search_knowledge for a signed-in patient.
create function public.public_search_knowledge(query text, query_embedding extensions.vector(1024), match_count integer default 5)
returns table (document_title text, heading text, content text, similarity real, keyword_match boolean)
language sql stable security definer set search_path = '' as $$
  select s.document_title, s.heading, s.content, s.similarity, s.keyword_match
  from public.search_knowledge(query, query_embedding, match_count) s
$$;
revoke all on function public.public_search_knowledge(text, extensions.vector, integer) from public;
grant execute on function public.public_search_knowledge(text, extensions.vector, integer) to anon, authenticated;
