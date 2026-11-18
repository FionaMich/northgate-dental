-- Linking a patient sign-in to a patient record, and parent proxies for children.
-- Front desk issues a one-time code (stored only as its SHA-256 hash, 7-day expiry, single use);
-- the patient redeems it in the app. Proxy access ends on the child's 18th birthday.
-- Row level security (Fiona reviews line by line): patients see only their own records and their children's.

create table public.patient_links (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  patient_id uuid not null unique references public.patients (id) on delete restrict,
  linked_at  timestamptz not null default now()
);

create table public.patient_proxies (
  proxy_profile_id uuid not null references public.profiles (id) on delete cascade,
  patient_id       uuid not null references public.patients (id) on delete restrict,
  ends_on          date not null,                       -- the child's 18th birthday
  linked_at        timestamptz not null default now(),
  primary key (proxy_profile_id, patient_id)
);

create table public.link_invitations (
  id         uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients (id) on delete restrict,
  kind       text not null check (kind in ('self', 'proxy')),
  code_hash  bytea not null unique,
  created_by uuid not null default auth.uid(),
  expires_at timestamptz not null default now() + interval '7 days',
  used_at    timestamptz,
  used_by    uuid references public.profiles (id) on delete set null
);
create index link_invitations_patient_idx on public.link_invitations (patient_id);

-- The patients this sign-in may see: their own record and children they are a proxy for.
create function private.my_patient_ids() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select l.patient_id from public.patient_links l where l.profile_id = auth.uid()
  union all
  select x.patient_id from public.patient_proxies x where x.proxy_profile_id = auth.uid() and current_date < x.ends_on
$$;
grant execute on function private.my_patient_ids() to authenticated;

-- Front desk, managers and org_admin, with 2FA, for a patient they can see. Returns the code once; it is never stored.
create function public.create_link_invitation(patient uuid, kind text default 'self') returns text
language plpgsql security definer set search_path = '' as $$
declare
  code text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 16));  -- 64 random bits
  dob  date;
begin
  if not (private.my_role() in ('receptionist', 'location_manager', 'org_admin')
          and private.passes_staff_gate() and private.can_see_patient(patient)) then
    raise exception 'not allowed to invite this patient' using errcode = 'insufficient_privilege';
  end if;
  select p.date_of_birth into dob from public.patients p where p.id = patient;
  if kind = 'proxy' and dob + interval '18 years' <= current_date then
    raise exception 'proxy access is only for patients under 18' using errcode = 'invalid_parameter_value';
  end if;
  insert into public.link_invitations (patient_id, kind, code_hash)
  values (patient, kind, pg_catalog.sha256(convert_to(code, 'UTF8')));
  return code;
end;
$$;

-- A signed-in patient redeems a code. Every failure gives the same message, so codes cannot be probed.
create function public.redeem_link_invitation(code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  inv public.link_invitations;
begin
  if private.my_role() is distinct from 'patient' then
    raise exception 'only patient accounts can redeem a code' using errcode = 'insufficient_privilege';
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

revoke execute on function public.create_link_invitation(uuid, text), public.redeem_link_invitation(text) from public, anon;
grant execute on function public.create_link_invitation(uuid, text), public.redeem_link_invitation(text) to authenticated;

------------------------------------------------------------------------------------------
-- Access: no direct writes to the new tables; the two functions above are the only way in.
------------------------------------------------------------------------------------------

grant select on public.patient_links, public.patient_proxies to authenticated;
revoke all on public.link_invitations from authenticated;   -- the default table grant would expose code_hash
grant select (id, patient_id, kind, created_by, expires_at, used_at) on public.link_invitations to authenticated;

do $$
declare t text;
begin
  foreach t in array array['patient_links', 'patient_proxies', 'link_invitations'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy staff_need_mfa on public.%I as restrictive for all to authenticated
                    using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()))', t);
    execute format('create trigger audit_row after insert or update or delete on public.%I
                    for each row execute function private.audit_row()', t);
  end loop;
  -- Patients read their own clinical records and appointments (history follows the appointment).
  foreach t in array array['patients', 'encounters', 'tooth_conditions', 'treatment_plans', 'plan_phases',
                           'dental_procedures', 'appointments'] loop
    execute format('create policy patient_reads_own_%s on public.%I for select to authenticated
                    using (%s in (select private.my_patient_ids()))', t, t, case t when 'patients' then 'id' else 'patient_id' end);
  end loop;
end;
$$;

create policy read_patient_links on public.patient_links for select to authenticated
  using (profile_id = (select auth.uid()) or private.can_see_patient(patient_id));
create policy read_patient_proxies on public.patient_proxies for select to authenticated
  using (proxy_profile_id = (select auth.uid()) or private.can_see_patient(patient_id));
create policy staff_read_link_invitations on public.link_invitations for select to authenticated
  using (private.is_staff() and private.can_see_patient(patient_id));
