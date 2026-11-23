-- Moving a visit in one step. Line-by-line review (Fiona): booking logic, and it decides which email a patient gets.
--
-- Before this, the app confirmed the new visit and then cancelled the old one in two calls: the patient got a
-- "booked" and a "cancelled" email, and if the second call failed both visits stood. Now one transaction does both,
-- through the same checks as confirm_booking and cancel_appointment, and the new visit records the visit it replaces,
-- so the worker sends a single "your visit has moved" email.
alter table public.appointments add column replaces uuid references public.appointments (id);

create function public.reschedule_booking(appointment uuid, old uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  -- Both visits must be the same patient's: a parent linked to two children cannot swap one child's visit for another's.
  if appointment = old or (select patient_id from public.appointments where id = appointment)
                        is distinct from (select patient_id from public.appointments where id = old) then
    raise exception 'these visits cannot be swapped' using errcode = 'invalid_parameter_value';
  end if;
  perform public.confirm_booking(appointment);   -- the caller's own, still-held slot
  perform public.cancel_appointment(old);        -- the caller's own, future visit
  update public.appointments set replaces = old where id = appointment;
end;
$$;

revoke all on function public.reschedule_booking(uuid, uuid) from public;
grant execute on function public.reschedule_booking(uuid, uuid) to authenticated;

-- For the worker: when the new visit is booked, the time it moved from; when the old visit is cancelled, the visit that
-- replaced it (so no separate "cancelled" email goes out). Nothing else about either visit.
create function private.reschedule_of(appointment uuid) returns table (moved_from timestamptz, replaced_by uuid)
language sql stable security definer set search_path = '' as $$
  select (select o.starts_at from public.appointments n join public.appointments o on o.id = n.replaces
           where n.id = reschedule_of.appointment),
         (select n.id from public.appointments n where n.replaces = reschedule_of.appointment);
$$;
revoke all on function private.reschedule_of(uuid) from public;
grant execute on function private.reschedule_of(uuid) to northgate_worker;
