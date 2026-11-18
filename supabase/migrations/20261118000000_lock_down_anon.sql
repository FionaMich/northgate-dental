-- Signed-out users (anon) get nothing by default on anything created in public.
-- Any access they need later is granted explicitly, table by table.
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke all on functions from anon;

-- Postgres lets every role (PUBLIC) run new functions, and anon is part of PUBLIC.
-- That default is global, so it must be removed globally; each function is then granted explicitly.
alter default privileges for role postgres revoke execute on functions from public;
