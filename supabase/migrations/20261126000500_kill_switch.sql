-- Section 12: the kill switch for the assistant (blueprint section 54).
-- Line-by-line review (Fiona): assistant safety.
--
-- org_settings.settings.assistant_enabled = false turns Nora off everywhere at once. Only an organisation admin with
-- two-factor can change org_settings (existing row level security; audited). The assistant service reads the switch
-- with the patient's own session through this function before every turn, and answers with a fixed text when it is off.
create function public.assistant_enabled() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select (s.settings ->> 'assistant_enabled')::boolean from public.org_settings s where s.id = 1), true)
$$;
revoke all on function public.assistant_enabled() from public;
grant execute on function public.assistant_enabled() to authenticated;
