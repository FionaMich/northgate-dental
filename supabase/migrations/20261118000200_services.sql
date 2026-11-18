-- Specialties, services, prices per location and rooms or equipment.
-- Money is always whole cents in an integer: $120.00 is 12000. No fractions, no floating point.

create type public.resource_kind as enum ('operatory', 'cbct_scanner', 'xray');

create table public.specialties (
  id   uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null
);

create table public.services (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique,                 -- CDT procedure code, for example D1110
  name              text not null,
  duration_minutes  int not null check (duration_minutes > 0),
  specialty_id      uuid references public.specialties (id) on delete restrict,
  requires_resource public.resource_kind,                 -- bookable only where this equipment exists
  active            boolean not null default true
);

create table public.location_services (
  location_id uuid not null references public.locations (id) on delete restrict,
  service_id  uuid not null references public.services (id) on delete restrict,
  price_cents integer not null check (price_cents >= 0),
  active      boolean not null default true,
  primary key (location_id, service_id)
);

create table public.resources (
  id          uuid primary key default gen_random_uuid(),
  location_id uuid not null references public.locations (id) on delete restrict,
  kind        public.resource_kind not null,
  name        text not null,
  active      boolean not null default true,
  unique (location_id, name)
);

alter table public.specialties       enable row level security;
alter table public.services          enable row level security;
alter table public.location_services enable row level security;
alter table public.resources         enable row level security;
