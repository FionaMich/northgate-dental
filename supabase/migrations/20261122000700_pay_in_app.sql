-- Paying in the app (Fiona, 2026-11-21): a signed-in patient gets a single-use pay link for their own visit.
-- Line-by-line review (Fiona): money. The amount still comes only from the price list (open_payment); the app gets a
-- token, never an amount it could change, and the link goes through W06 and W04 to Stripe Checkout.
create function public.start_my_payment(appointment uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  payment uuid;
begin
  if not private.passes_patient_gate()
     or not exists (select 1 from public.appointments a
                     where a.id = start_my_payment.appointment and a.patient_id in (select private.my_patient_ids())) then
    raise exception 'this visit is not yours to pay for' using errcode = 'insufficient_privilege';
  end if;
  select o.payment_id into payment from private.open_payment(appointment) o;
  return private.issue_action_token(appointment, 'pay', 'app', payment);
end;
$$;
revoke all on function public.start_my_payment(uuid) from public;
grant execute on function public.start_my_payment(uuid) to authenticated;
