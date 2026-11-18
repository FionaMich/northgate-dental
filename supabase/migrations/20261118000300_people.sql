-- People: sign-in profiles with roles, practitioners, where staff work, and the roster.

create type public.app_role as enum ('patient', 'receptionist', 'clinician', 'location_manager', 'org_admin');

-- One profile per sign-in. Accounts are deactivated, never deleted, so history keeps its owner.
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete restrict,
  role         public.app_role not null default 'patient',
  display_name text,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

-- Helpers that policies and triggers use to learn who is calling. security definer so they can read
-- profiles whatever the caller's row level security allows; empty search_path so nothing can be swapped in.
grant usage on schema private to authenticated;

create function private.my_role() returns public.app_role
language sql stable security definer set search_path = '' as $$
  select p.role from public.profiles p where p.id = auth.uid() and p.active
$$;

create function private.is_org_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.my_role() = 'org_admin', false)
$$;

grant execute on function private.my_role(), private.is_org_admin() to authenticated;

-- E13: through the API, only an organisation administrator can set or change a role.
-- Migrations, seeds and server jobs run as other database roles and are not affected.
create function private.guard_role_change() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user in ('authenticated', 'anon')
     and (tg_op = 'INSERT' and new.role <> 'patient' or tg_op = 'UPDATE' and new.role is distinct from old.role)
     and not private.is_org_admin() then
    raise exception 'only an organisation administrator can change a role' using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

create trigger profiles_guard_role_change
  before insert or update of role on public.profiles
  for each row execute function private.guard_role_change();

create table public.practitioners (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid unique references public.profiles (id) on delete restrict,
  display_name text not null,
  npi          text check (npi ~ '^[0-9]{10}$'),   -- US National Provider Identifier
  active       boolean not null default true
);

-- Where and as what each practitioner works; the weekly template is validated when slots are built (section 04).
create table public.practitioner_roles (
  id              uuid primary key default gen_random_uuid(),
  practitioner_id uuid not null references public.practitioners (id) on delete restrict,
  location_id     uuid not null references public.locations (id) on delete restrict,
  specialty_id    uuid not null references public.specialties (id) on delete restrict,
  weekly_template jsonb not null default '{}' check (jsonb_typeof(weekly_template) = 'object'),
  unique (practitioner_id, location_id, specialty_id)
);

-- Which locations each staff member can see and work at; row level security reads this (T5).
create table public.staff_locations (
  profile_id  uuid not null references public.profiles (id) on delete restrict,
  location_id uuid not null references public.locations (id) on delete restrict,
  primary key (profile_id, location_id)
);

-- Who worked or was on call where and when, kept as history. One person, one place at a time (E12).
create table public.staff_roster (
  id              uuid primary key default gen_random_uuid(),
  practitioner_id uuid not null references public.practitioners (id) on delete restrict,
  location_id     uuid not null references public.locations (id) on delete restrict,
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  on_call         boolean not null default false,
  check (ends_at > starts_at),
  exclude using gist (practitioner_id with =, tstzrange(starts_at, ends_at, '[)') with &&)
);

alter table public.profiles           enable row level security;
alter table public.practitioners      enable row level security;
alter table public.practitioner_roles enable row level security;
alter table public.staff_locations    enable row level security;
alter table public.staff_roster       enable row level security;
