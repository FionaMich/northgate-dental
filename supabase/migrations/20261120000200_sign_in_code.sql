-- Password plus emailed code at every patient sign-in (decision 2026-11-20). Supabase Auth emails the code
-- (the same mail path as the sign-up code); the database decides what a session may see:
--   1. password accepted  -> the app calls start_sign_in_code(): a password proof for this user, 10 minutes;
--   2. emailed code accepted (a new session) -> the app calls finish_sign_in_code(): needs that fresh proof,
--      and marks this session verified. A brand-new account's first session is verified by its sign-up code.
-- Patient data flows only through my_patient_ids(), which now returns nothing for an unverified session,
-- so a stolen password alone, or a stolen inbox alone, reads no patient data (E43, E46).
-- Row level security and identity: Fiona reviews line by line.

create table private.password_proofs (
  user_id   uuid primary key references auth.users (id) on delete cascade,
  proved_at timestamptz not null default now()
);

-- One row per verified session; signing out deletes the auth session and, with it, this row.
create table private.verified_sessions (
  session_id  uuid primary key references auth.sessions (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  verified_at timestamptz not null default now()
);

create function private.signed_in_with(method text) returns boolean
language sql stable set search_path = '' as $$
  select coalesce(auth.jwt() -> 'amr', '[]'::jsonb) @> jsonb_build_array(jsonb_build_object('method', method))
$$;

create function private.passes_patient_gate() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from private.verified_sessions v
                  where v.session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid and v.user_id = auth.uid())
$$;
grant execute on function private.signed_in_with(text), private.passes_patient_gate() to authenticated;

-- Step 1, called with the password session.
create function public.start_sign_in_code() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if private.my_role() is distinct from 'patient' or not private.signed_in_with('password') then
    raise exception 'sign in with your password first' using errcode = 'insufficient_privilege';
  end if;
  insert into private.password_proofs (user_id) values (auth.uid())
  on conflict (user_id) do update set proved_at = now();
end;
$$;

-- Step 2, called with the session the emailed code created.
create function public.finish_sign_in_code() returns void
language plpgsql security definer set search_path = '' as $$
declare
  me      uuid := auth.uid();
  session uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
begin
  if private.my_role() is distinct from 'patient' or session is null or not private.signed_in_with('otp') then
    raise exception 'enter the code from your email' using errcode = 'insufficient_privilege';
  end if;
  if exists (select 1 from private.password_proofs p where p.user_id = me and p.proved_at > now() - interval '10 minutes') then
    delete from private.password_proofs p where p.user_id = me;            -- one proof, one session
  elsif not (exists (select 1 from auth.users u
                      where u.id = me and u.created_at > now() - interval '30 minutes'
                        and u.email_confirmed_at > now() - interval '15 minutes')
             and not exists (select 1 from private.verified_sessions v where v.user_id = me)) then
    raise exception 'sign in with your password first' using errcode = 'insufficient_privilege';
  end if;
  insert into private.verified_sessions (session_id, user_id) values (session, me) on conflict (session_id) do nothing;
end;
$$;

create function public.session_is_verified() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.my_role() is distinct from 'patient' or private.passes_patient_gate()
$$;

revoke execute on function public.start_sign_in_code(), public.finish_sign_in_code(), public.session_is_verified() from public, anon;
grant execute on function public.start_sign_in_code(), public.finish_sign_in_code(), public.session_is_verified() to authenticated;

-- The gate, in the two functions every patient read and write goes through.
create or replace function private.my_patient_ids() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select l.patient_id from public.patient_links l
   where l.profile_id = auth.uid() and private.passes_patient_gate()
  union all
  select x.patient_id from public.patient_proxies x
   where x.proxy_profile_id = auth.uid() and current_date < x.ends_on and private.passes_patient_gate()
$$;

create or replace function private.my_clinical_patient_ids() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select l.patient_id from public.patient_links l
   where l.profile_id = auth.uid() and private.passes_patient_gate()
  union all
  select x.patient_id
    from public.patient_proxies x join public.patients p on p.id = x.patient_id
   where x.proxy_profile_id = auth.uid() and current_date < x.ends_on and private.passes_patient_gate()
     and (p.date_of_birth + interval '13 years' > current_date
          or coalesce((select (s.settings ->> 'teen_proxy_full_access')::boolean from public.org_settings s), false))
$$;

-- Linking also needs a verified session (same function bodies as before, plus the gate).
create or replace function public.redeem_link_invitation(code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  inv public.link_invitations;
begin
  if private.my_role() is distinct from 'patient' then
    raise exception 'only patient accounts can redeem a code' using errcode = 'insufficient_privilege';
  end if;
  if not private.passes_patient_gate() then
    raise exception 'enter the code from your email first' using errcode = 'insufficient_privilege';
  end if;
  update public.link_invitations i set used_at = now(), used_by = auth.uid()
   where i.code_hash = pg_catalog.sha256(convert_to(upper(trim(code)), 'UTF8'))
     and i.used_at is null and i.expires_at > now()
  returning * into inv;
  if inv.id is null then
    raise exception 'this code is not valid or has expired' using errcode = 'invalid_parameter_value';
  end if;
  if inv.kind = 'self' then
    insert into public.patient_links (profile_id, patient_id) values (auth.uid(), inv.patient_id);
  else
    insert into public.patient_proxies (proxy_profile_id, patient_id, ends_on)
    select auth.uid(), p.id, (p.date_of_birth + interval '18 years')::date from public.patients p where p.id = inv.patient_id;
  end if;
  return inv.patient_id;
end;
$$;
create or replace function public.link_by_birth_date(birth_date date) returns text
language plpgsql security definer set search_path = '' as $$
declare
  me     uuid := auth.uid();
  mail   text;
  found  uuid[];
begin
  if private.my_role() is distinct from 'patient' then
    raise exception 'only patient accounts can link a record' using errcode = 'insufficient_privilege';
  end if;
  if not private.passes_patient_gate() then
    raise exception 'enter the code from your email first' using errcode = 'insufficient_privilege';
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
