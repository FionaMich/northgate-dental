-- The organisation, its locations, opening hours, closures and settings.
-- Every table has row level security from the start, so each stays closed until a policy opens it (section 02, T5).

create extension if not exists btree_gist with schema extensions;

create schema if not exists private;
revoke all on schema private from public;

-- One organisation per database.
create table public.organisation (
  id             int primary key default 1 check (id = 1),
  name           text not null,
  schedule_owner text not null default 'platform' check (schedule_owner in ('platform', 'ehr')),
  is_synthetic   boolean not null default true
);

create table public.locations (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique check (code ~ '^[a-z0-9-]+$'),
  name         text not null,
  address_line text,
  city         text,
  state        text check (state ~ '^[A-Z]{2}$'),
  postal_code  text,
  time_zone    text not null,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

-- Refuse a time zone Postgres does not know, so local hours always convert correctly.
create function private.check_time_zone() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.time_zone) then
    raise exception 'unknown time zone: %', new.time_zone using errcode = 'invalid_parameter_value';
  end if;
  return new;
end;
$$;

create trigger locations_check_time_zone
  before insert or update of time_zone on public.locations
  for each row execute function private.check_time_zone();

-- Opening hours are local clock times (weekday 1 is Monday); the location's time zone turns them into instants.
create table public.location_hours (
  id          uuid primary key default gen_random_uuid(),
  location_id uuid not null references public.locations (id) on delete restrict,
  weekday     smallint not null check (weekday between 1 and 7),
  opens       time not null,
  closes      time not null,
  check (closes > opens),
  exclude using gist (
    location_id with =,
    weekday with =,
    tsrange('2000-01-01'::date + opens, '2000-01-01'::date + closes) with &&
  )
);

-- Whole days or part of a day.
create table public.location_closures (
  id          uuid primary key default gen_random_uuid(),
  location_id uuid not null references public.locations (id) on delete restrict,
  starts_at   timestamptz not null,
  ends_at     timestamptz not null,
  reason      text not null,
  check (ends_at > starts_at)
);

-- Organisation defaults and per-location overrides; the view merges them key by key, override wins.
create table public.org_settings (
  id       int primary key default 1 check (id = 1),
  settings jsonb not null default '{}' check (jsonb_typeof(settings) = 'object')
);

create table public.location_settings (
  location_id uuid primary key references public.locations (id) on delete restrict,
  overrides   jsonb not null default '{}' check (jsonb_typeof(overrides) = 'object')
);

-- security_invoker: the caller's row level security applies through the view.
create view public.effective_location_settings with (security_invoker = true) as
select l.id as location_id,
       coalesce(o.settings, '{}'::jsonb) || coalesce(s.overrides, '{}'::jsonb) as settings
from public.locations l
left join public.org_settings o on o.id = 1
left join public.location_settings s on s.location_id = l.id;

alter table public.organisation      enable row level security;
alter table public.locations         enable row level security;
alter table public.location_hours    enable row level security;
alter table public.location_closures enable row level security;
alter table public.org_settings      enable row level security;
alter table public.location_settings enable row level security;
