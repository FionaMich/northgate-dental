-- The MCP server's public search: signed-out callers get approved passages through one function, never the tables.
begin;
select plan(3);

insert into knowledge_documents (id, slug, title, version, checksum) values
  ('91000000-0000-4000-8000-000000000001', 'cancellations', 'Cancellations and missed visits', '1', 'a');
insert into knowledge_passages (document_id, ordinal, heading, content) values
  ('91000000-0000-4000-8000-000000000001', 1, 'Missed visits', 'A visit missed without 24 hours notice has a no-show fee of $50.');

set local role anon;
select is((select document_title from public.public_search_knowledge('no-show fee', null, 3) limit 1),
  'Cancellations and missed visits', 'a visitor finds the approved policy');
select throws_ok($$ select count(*) from knowledge_passages $$, '42501', null, 'but still cannot read the table itself');
select throws_ok($$ select * from public.search_knowledge('fee', null, 3) $$, '42501', null,
  'and the signed-in search stays closed to visitors');
reset role;

select * from finish();
rollback;
