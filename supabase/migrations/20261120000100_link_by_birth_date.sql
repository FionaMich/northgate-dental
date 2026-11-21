-- Linking without a front-desk code (decision 2026-11-20). The emailed sign-up code has already proved the
-- email address; the record must use that same email, belong to an adult, not be linked yet, and the patient
-- confirms its date of birth. Five misses in 24 hours lock this route; the front-desk code still works.
-- Row level security and identity: Fiona reviews line by line.

-- Misses only; never readable by app users. Kept 24 hours for the lock-out, then ignored.
create table private.link_attempts (
  profile_id   uuid not null references public.profiles (id) on delete cascade,
  attempted_at timestamptz not null default now()
);
create index link_attempts_profile_idx on private.link_attempts (profile_id, attempted_at);

-- Returns 'linked', 'no_match' or 'locked'. It returns instead of raising, so a miss is recorded
-- (an exception would roll the record back). Every miss gives the same answer, so nothing is revealed.
create function public.link_by_birth_date(birth_date date) returns text
language plpgsql security definer set search_path = '' as $$
declare
  me     uuid := auth.uid();
  mail   text;
  found  uuid[];
begin
  if private.my_role() is distinct from 'patient' then
    raise exception 'only patient accounts can link a record' using errcode = 'insufficient_privilege';
  end if;
  if exists (select 1 from public.patient_links l where l.profile_id = me) then
    return 'linked';
  end if;
  if (select count(*) from private.link_attempts a where a.profile_id = me and a.attempted_at > now() - interval '24 hours') >= 5 then
    return 'locked';
  end if;

  select lower(u.email) into mail from auth.users u where u.id = me and u.email_confirmed_at is not null;
  select array_agg(p.id) into found
    from public.patients p
   where mail is not null
     and lower(p.email) = mail
     and p.date_of_birth = birth_date
     and p.date_of_birth + interval '18 years' <= current_date
     and p.deceased_at is null
     and not exists (select 1 from public.patient_links l where l.patient_id = p.id);

  if coalesce(array_length(found, 1), 0) <> 1 then
    insert into private.link_attempts (profile_id) values (me);
    return case when (select count(*) from private.link_attempts a
                       where a.profile_id = me and a.attempted_at > now() - interval '24 hours') >= 5
                then 'locked' else 'no_match' end;
  end if;
  insert into public.patient_links (profile_id, patient_id) values (me, found[1]);  -- audited by its trigger
  return 'linked';
end;
$$;
revoke execute on function public.link_by_birth_date(date) from public, anon;
grant execute on function public.link_by_birth_date(date) to authenticated;
