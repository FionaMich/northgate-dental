-- Insurance plans patients pick from when adding a card (Fiona, 2026-11-20). Reference data, no patient data.
-- Commercial plans have fictional names (blueprint 51: synthetic data never imitates a real company);
-- the public programmes keep their real names. Which clinic accepts which plan comes with eligibility (section 11).
-- Row level security: Fiona reviews line by line.

create table public.insurance_plans (
  id     uuid primary key default gen_random_uuid(),
  name   text not null unique,
  kind   text not null check (kind in ('commercial', 'medicaid', 'medicare')),
  active boolean not null default true
);

alter table public.insurance_plans enable row level security;
create policy staff_need_mfa on public.insurance_plans as restrictive for all to authenticated
  using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()));
create trigger audit_row after insert or update or delete on public.insurance_plans
  for each row execute function private.audit_row();

revoke all on public.insurance_plans from anon, authenticated;
grant select on public.insurance_plans to authenticated;
grant insert, update on public.insurance_plans to authenticated;   -- the policy limits writes to org_admin

create policy read_insurance_plans on public.insurance_plans for select to authenticated
  using (active or (select private.is_staff()));
create policy admin_writes_insurance_plans on public.insurance_plans for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));

-- A card points at the plan picked; payer_name keeps the name as entered (or typed, when not listed).
alter table public.coverages add column plan_id uuid references public.insurance_plans (id) on delete restrict;
create index coverages_plan_idx on public.coverages (plan_id);
grant insert (plan_id) on public.coverages to authenticated;

insert into public.insurance_plans (name, kind) values
  ('Harborline Dental PPO',            'commercial'),
  ('Harborline Dental HMO',            'commercial'),
  ('Beacon Mutual Dental',             'commercial'),
  ('Commonwealth Smile Plan',          'commercial'),
  ('Granite Shore Dental Alliance',    'commercial'),
  ('Pilgrim Health Dental',            'commercial'),
  ('Seaport Benefits Dental',          'commercial'),
  ('Charles River Employee Dental',    'commercial'),
  ('MassHealth Dental',                'medicaid'),
  ('Medicare Advantage with dental',   'medicare');
