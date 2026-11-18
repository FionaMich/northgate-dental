-- Append-only audit log: every insert, update and delete on every table, with who did it and in which role.
-- Nobody signed in, and no server code, can change or remove an entry.

create table public.audit_log (
  id          bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_id    uuid,                 -- null when a migration, seed or database job made the change
  actor_role  public.app_role,
  table_name  text not null,
  row_pk      text not null check (row_pk <> ''),  -- a table whose key cannot be read fails loudly
  action      text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  old_row     jsonb,
  new_row     jsonb
);

alter table public.audit_log enable row level security;

revoke all on public.audit_log from anon, authenticated, service_role;
grant select on public.audit_log to authenticated;

create policy staff_need_mfa on public.audit_log as restrictive for all to authenticated
  using ((select private.my_role()) is not null and (not (select private.is_staff()) or (select private.has_mfa())))
  with check ((select private.my_role()) is not null and (not (select private.is_staff()) or (select private.has_mfa())));
create policy admin_reads_audit_log on public.audit_log for select to authenticated
  using ((select private.is_org_admin()));

-- security definer: writes the entry even though callers cannot insert into audit_log themselves.
create function private.audit_row() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  r jsonb := coalesce(to_jsonb(new), to_jsonb(old));
begin
  insert into public.audit_log (actor_id, actor_role, table_name, row_pk, action, old_row, new_row)
  values (
    auth.uid(),
    private.my_role(),
    tg_table_name,
    coalesce(r ->> 'id', concat_ws(':', r ->> 'location_id', r ->> 'service_id', r ->> 'profile_id')),
    tg_op,
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end
  );
  return null;
end;
$$;

-- Tables that exist now. A table added later must add this trigger in its own migration;
-- test 06_audit fails CI for any table without it.
do $$
declare t text;
begin
  for t in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' and c.relname <> 'audit_log'
  loop
    execute format('create trigger audit_row after insert or update or delete on public.%I
                    for each row execute function private.audit_row()', t);
  end loop;
end;
$$;
