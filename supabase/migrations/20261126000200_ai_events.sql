-- Section 10: every assistant turn is logged (AGENTS.md section 9, "Every AI action is logged to ai_events").
-- Line-by-line review (Fiona): assistant safety.
--
-- One row per turn, with the shape of the turn only: channel, language, outcome, the names of the tools Nora called,
-- the model and prompt version that answered, how long it took and how many tokens it used. Never the patient's words
-- or Nora's reply: those stay in the assistant's checkpoint store. The patient comes from the session, as in
-- request_handover. Rows are append-only: no update or delete grant for anyone through the API.

create table public.ai_events (
  id             uuid primary key default gen_random_uuid(),
  patient_id     uuid not null references public.patients (id) on delete restrict,
  channel        text not null check (channel in ('chat', 'call')),
  language       text not null check (char_length(language) between 2 and 8),
  outcome        text not null check (outcome in ('answered', 'confirm', 'handover', 'emergency')),
  -- tool names only: lower-case words joined by underscores, so no sentence can be stored as a "tool"
  tools          text[] not null default '{}' check (array_to_string(tools, ',') ~ '^([a-z_]{1,40}(,|$))*$'),
  model          text not null check (char_length(model) between 1 and 80),
  prompt_version text not null check (char_length(prompt_version) between 1 and 40),
  latency_ms     integer not null check (latency_ms >= 0),
  input_tokens   integer not null default 0 check (input_tokens >= 0),
  output_tokens  integer not null default 0 check (output_tokens >= 0),
  created_at     timestamptz not null default now()
);
create index ai_events_patient_time on public.ai_events (patient_id, created_at desc);
alter table public.ai_events enable row level security;
create trigger audit_row after insert or update or delete on public.ai_events
  for each row execute function private.audit_row();
create policy staff_need_mfa on public.ai_events as restrictive for all to authenticated
  using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()));
revoke all on public.ai_events from anon, authenticated;
grant select on public.ai_events to authenticated;
create policy patient_reads_own_ai_events on public.ai_events for select to authenticated
  using (patient_id in (select private.my_patient_ids()));
create policy staff_reads_ai_events on public.ai_events for select to authenticated
  using (private.is_staff() and private.can_see_patient(patient_id));

create function public.log_ai_event(channel text, language text, outcome text, tools text[], model text,
                                    prompt_version text, latency_ms integer, input_tokens integer,
                                    output_tokens integer) returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select l.patient_id from public.patient_links l where l.profile_id = auth.uid());
begin
  if not private.passes_patient_gate() or me is null then
    raise exception 'sign in with a linked patient record first' using errcode = 'insufficient_privilege';
  end if;
  insert into public.ai_events (patient_id, channel, language, outcome, tools, model, prompt_version, latency_ms,
                                input_tokens, output_tokens)
  values (me, log_ai_event.channel, log_ai_event.language, log_ai_event.outcome, coalesce(log_ai_event.tools, '{}'),
          log_ai_event.model, log_ai_event.prompt_version, log_ai_event.latency_ms,
          coalesce(log_ai_event.input_tokens, 0), coalesce(log_ai_event.output_tokens, 0));
end;
$$;
revoke all on function public.log_ai_event(text, text, text, text[], text, text, integer, integer, integer) from public;
grant execute on function public.log_ai_event(text, text, text, text[], text, text, integer, integer, integer) to authenticated;
