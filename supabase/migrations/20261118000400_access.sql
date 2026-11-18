-- Who can see and change what. Reviewed line by line by Fiona (row level security).
--
-- Roles: patient, receptionist, clinician, location_manager, org_admin (profiles.role).
-- Staff see the locations listed for them in staff_locations; org_admin sees everything.
-- Staff see nothing at all until their session has a verified second factor (aal2).
-- Patients see public information (locations, hours, closures, services, prices) at active locations.
-- Signed-out users (anon) have no grants at all (T1).

------------------------------------------------------------------------------------------
-- Helpers. security definer so they can read profiles and staff_locations whatever the
-- caller's own rules allow (this also avoids policies calling themselves); empty search_path.
------------------------------------------------------------------------------------------

create function private.is_staff() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.my_role() in ('receptionist', 'clinician', 'location_manager', 'org_admin'), false)
$$;

create function private.has_mfa() returns boolean
language sql stable set search_path = '' as $$
  select coalesce(auth.jwt() ->> 'aal' = 'aal2', false)
$$;

create function private.my_location_ids() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select sl.location_id from public.staff_locations sl
   where sl.profile_id = auth.uid() and private.is_staff()
$$;

create function private.manages(loc uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.my_role() = 'location_manager' and loc in (select private.my_location_ids())
$$;

create function private.current_practitioner_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select pr.id from public.practitioners pr where pr.profile_id = auth.uid() and pr.active
$$;

create function private.role_of(profile uuid) returns public.app_role
language sql stable security definer set search_path = '' as $$
  select p.role from public.profiles p where p.id = profile
$$;

create function private.is_active_location(loc uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select l.active from public.locations l where l.id = loc), false)
$$;

grant execute on function
  private.is_staff(), private.has_mfa(), private.my_location_ids(), private.manages(uuid),
  private.current_practitioner_id(), private.role_of(uuid), private.is_active_location(uuid)
  to authenticated;

------------------------------------------------------------------------------------------
-- Grants: what a signed-in user may attempt at all. Row level security then decides which rows.
-- No TRUNCATE (row level security does not apply to it), REFERENCES or TRIGGER for anyone signed in.
-- Tables added later start read-only; each later migration grants writes explicitly.
------------------------------------------------------------------------------------------

revoke all on all tables in schema public from authenticated;
alter default privileges for role postgres in schema public revoke insert, update, delete, truncate, references, trigger on tables from authenticated;

grant select on all tables in schema public to authenticated;
grant insert, update on public.organisation, public.locations, public.org_settings, public.location_settings,
  public.specialties, public.services, public.location_services, public.practitioners,
  public.practitioner_roles to authenticated;
grant insert (id, role, display_name, active), update (display_name, role, active) on public.profiles to authenticated;
grant insert, update, delete on public.location_hours, public.location_closures, public.resources,
  public.staff_roster to authenticated;
grant insert, delete on public.staff_locations to authenticated;

------------------------------------------------------------------------------------------
-- E05: staff see and change nothing without a verified second factor, and nobody without an active
-- profile (deactivated, or not yet set up) sees or changes anything. Restrictive, so it is combined
-- with AND on top of every other policy on the table.
------------------------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array[
    'organisation', 'locations', 'location_hours', 'location_closures', 'org_settings', 'location_settings',
    'specialties', 'services', 'location_services', 'resources',
    'profiles', 'practitioners', 'practitioner_roles', 'staff_locations', 'staff_roster'
  ] loop
    execute format(
      'create policy staff_need_mfa on public.%I as restrictive for all to authenticated
         using ((select private.my_role()) is not null and (not (select private.is_staff()) or (select private.has_mfa())))
         with check ((select private.my_role()) is not null and (not (select private.is_staff()) or (select private.has_mfa())))', t);
  end loop;
end;
$$;

------------------------------------------------------------------------------------------
-- Organisation and settings
------------------------------------------------------------------------------------------

create policy read_organisation on public.organisation for select to authenticated
  using ((select private.my_role()) is not null);
create policy admin_writes_organisation on public.organisation for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));

create policy read_org_settings on public.org_settings for select to authenticated
  using ((select private.is_staff()));
create policy admin_writes_org_settings on public.org_settings for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));

create policy read_location_settings on public.location_settings for select to authenticated
  using ((select private.is_org_admin()) or location_id in (select private.my_location_ids()));
create policy admin_writes_location_settings on public.location_settings for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));

------------------------------------------------------------------------------------------
-- Locations, hours, closures (E04, E06, E14, E17). No delete policy on locations: nobody deletes one.
------------------------------------------------------------------------------------------

create policy read_locations on public.locations for select to authenticated
  using ((select private.is_org_admin())
         or id in (select private.my_location_ids())
         or ((select private.my_role()) = 'patient' and active));
create policy admin_inserts_locations on public.locations for insert to authenticated
  with check ((select private.is_org_admin()));
create policy admin_updates_locations on public.locations for update to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));

create policy read_location_hours on public.location_hours for select to authenticated
  using ((select private.is_org_admin())
         or location_id in (select private.my_location_ids())
         or ((select private.my_role()) = 'patient' and private.is_active_location(location_id)));
create policy manage_location_hours on public.location_hours for all to authenticated
  using ((select private.is_org_admin()) or private.manages(location_id))
  with check ((select private.is_org_admin()) or private.manages(location_id));

create policy read_location_closures on public.location_closures for select to authenticated
  using ((select private.is_org_admin())
         or location_id in (select private.my_location_ids())
         or ((select private.my_role()) = 'patient' and private.is_active_location(location_id)));
create policy manage_location_closures on public.location_closures for all to authenticated
  using ((select private.is_org_admin()) or private.manages(location_id))
  with check ((select private.is_org_admin()) or private.manages(location_id));

------------------------------------------------------------------------------------------
-- Services and prices. Only org_admin changes a price (money: line-by-line review).
------------------------------------------------------------------------------------------

create policy read_specialties on public.specialties for select to authenticated
  using ((select private.my_role()) is not null);
create policy admin_writes_specialties on public.specialties for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));

create policy read_services on public.services for select to authenticated
  using ((select private.is_staff()) or ((select private.my_role()) = 'patient' and active));
create policy admin_writes_services on public.services for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));

create policy read_location_services on public.location_services for select to authenticated
  using ((select private.is_org_admin())
         or location_id in (select private.my_location_ids())
         or ((select private.my_role()) = 'patient' and active and private.is_active_location(location_id)
             and exists (select 1 from public.services s where s.id = service_id and s.active)));
create policy admin_writes_location_services on public.location_services for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));

create policy read_resources on public.resources for select to authenticated
  using ((select private.is_org_admin()) or location_id in (select private.my_location_ids()));
create policy manage_resources on public.resources for all to authenticated
  using ((select private.is_org_admin()) or private.manages(location_id))
  with check ((select private.is_org_admin()) or private.manages(location_id));

------------------------------------------------------------------------------------------
-- People (E13, E16). A user may edit their own profile, but the guard below keeps role and
-- active for org_admin only.
------------------------------------------------------------------------------------------

create policy read_profiles on public.profiles for select to authenticated
  using (id = auth.uid()
         or (select private.is_org_admin())
         or ((select private.my_role()) = 'location_manager'
             and exists (select 1 from public.staff_locations sl
                          where sl.profile_id = profiles.id and private.manages(sl.location_id))));
create policy admin_inserts_profiles on public.profiles for insert to authenticated
  with check ((select private.is_org_admin()));
create policy update_own_or_admin_profiles on public.profiles for update to authenticated
  using (id = auth.uid() or (select private.is_org_admin()))
  with check (id = auth.uid() or (select private.is_org_admin()));

-- The guard from T4 now also protects the active flag, so a deactivated user cannot reactivate themselves.
create or replace function private.guard_role_change() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user in ('authenticated', 'anon')
     and not (select private.is_org_admin())
     and (   (tg_op = 'INSERT' and new.role <> 'patient')
          or (tg_op = 'UPDATE' and (new.role is distinct from old.role or new.active is distinct from old.active))) then
    raise exception 'only an organisation administrator can change a role or the active flag' using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

drop trigger profiles_guard_role_change on public.profiles;
create trigger profiles_guard_role_change
  before insert or update of role, active on public.profiles
  for each row execute function private.guard_role_change();

create policy read_practitioners on public.practitioners for select to authenticated
  using ((select private.is_staff()));
create policy admin_writes_practitioners on public.practitioners for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));

create policy read_practitioner_roles on public.practitioner_roles for select to authenticated
  using ((select private.is_org_admin()) or location_id in (select private.my_location_ids()));
create policy admin_writes_practitioner_roles on public.practitioner_roles for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));

create policy read_staff_locations on public.staff_locations for select to authenticated
  using ((select private.is_org_admin()) or profile_id = auth.uid() or private.manages(location_id));
-- A manager assigns and removes receptionists and clinicians at their own locations only;
-- only org_admin can give a manager or administrator access to a location.
create policy manage_staff_locations on public.staff_locations for all to authenticated
  using ((select private.is_org_admin())
         or (private.manages(location_id) and private.role_of(profile_id) in ('receptionist', 'clinician')))
  with check ((select private.is_org_admin())
         or (private.manages(location_id) and private.role_of(profile_id) in ('receptionist', 'clinician')));

create policy read_staff_roster on public.staff_roster for select to authenticated
  using ((select private.is_org_admin())
         or location_id in (select private.my_location_ids())
         or practitioner_id = (select private.current_practitioner_id()));
create policy manage_staff_roster on public.staff_roster for all to authenticated
  using ((select private.is_org_admin()) or private.manages(location_id))
  with check ((select private.is_org_admin()) or private.manages(location_id));
