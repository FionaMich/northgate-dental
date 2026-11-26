-- Section 11: continuous dental care, workflows W24 to W28 (blueprint section 8 for Northgate).
-- Line-by-line review (Fiona): row level security; anything that messages a patient; the safety rules (W25, W28).
--
-- Three programmes a clinician invites a patient to, and the patient joins with recorded consent:
--   post_procedure  daily check-ins for the days after an extraction, implant, root canal or similar
--   aligners        the daily aligner wear the patient chooses to share from the app's timer
--   recall          the six-monthly check-up reminder
-- W24 opens each day's check-in (10:00 clinic time); W25 applies fixed rules and clinician thresholds to each answer
-- (nudge, care task or the emergency path; no model reads a check-in); W26 writes a weekly summary for the clinician
-- from the data points only; W27 nudges missed check-ins and short wear with approved templates, never between 20:00
-- and 09:00; W28 raises check-up flags (serious side effect, worsening trend, repeated missed wear or check-ins) as a
-- care task with a booking offer, open until a clinician records the outcome. Queue messages carry IDs only.
-- Medicines (dose schedules, missed-dose advice) are not here: they need approved label sources first.

create table public.care_enrolments (
  id                uuid primary key default gen_random_uuid(),
  patient_id        uuid not null references public.patients (id) on delete restrict,
  location_id       uuid not null references public.locations (id) on delete restrict,
  programme         text not null check (programme in ('post_procedure', 'aligners', 'recall')),
  appointment_id    uuid references public.appointments (id) on delete set null,
  starts_on         date not null default current_date,
  ends_on           date not null,
  wear_target_hours numeric(4, 1) not null default 22 check (wear_target_hours between 12 and 24),
  status            text not null default 'invited' check (status in ('invited', 'active', 'completed', 'withdrawn')),
  consent_at        timestamptz,
  created_by        uuid references public.profiles (id),
  created_at        timestamptz not null default now(),
  check (ends_on >= starts_on),
  check (status not in ('active', 'completed') or consent_at is not null)
);
create unique index care_enrolments_one_open on public.care_enrolments (patient_id, programme) where status in ('invited', 'active');

-- Clinician-set thresholds per programme (blueprint: "applies clinician thresholds"); defaults below.
create table public.care_thresholds (
  programme text not null check (programme in ('post_procedure', 'aligners', 'recall')),
  rule      text not null,
  value     numeric not null,
  primary key (programme, rule)
);
insert into public.care_thresholds (programme, rule, value) values
  ('post_procedure', 'pain_task', 7),            -- pain at or above this opens a care task
  ('post_procedure', 'worse_after_day', 3),      -- "worse" after this many days opens a care task
  ('post_procedure', 'missed_checkins_flag', 2), -- missed check-ins in a row before a check-up flag
  ('aligners', 'short_by_hours', 2),             -- a day this far under the target counts as short
  ('aligners', 'short_days_nudge', 2),           -- short days in a row before a nudge
  ('aligners', 'short_days_flag', 5);            -- short days in the last 7 before a check-up flag

create table public.care_checkins (
  id           uuid primary key default gen_random_uuid(),
  enrolment_id uuid not null references public.care_enrolments (id) on delete cascade,
  patient_id   uuid not null references public.patients (id) on delete restrict,
  due_on       date not null,
  pain         smallint check (pain between 0 and 10),
  feeling      text check (feeling in ('better', 'same', 'worse')),
  symptoms     text[] not null default '{}' check (symptoms <@ array['bleeding', 'swelling', 'fever', 'numbness', 'bad_taste']),
  note         text check (char_length(note) <= 500),
  red_flags    text[] not null default '{}',
  level        text check (level in ('ok', 'nudge', 'task', 'emergency')),
  answered_at  timestamptz,
  unique (enrolment_id, due_on)
);

create table public.aligner_wear (
  enrolment_id uuid not null references public.care_enrolments (id) on delete cascade,
  patient_id   uuid not null references public.patients (id) on delete restrict,
  day          date not null,
  hours        numeric(4, 1) not null check (hours between 0 and 24),
  primary key (enrolment_id, day)
);

create table public.care_flags (
  id           uuid primary key default gen_random_uuid(),
  enrolment_id uuid not null references public.care_enrolments (id) on delete cascade,
  patient_id   uuid not null references public.patients (id) on delete restrict,
  reason       text not null check (reason in ('serious_side_effect', 'worsening_trend', 'missed_wear', 'missed_checkins')),
  data         jsonb not null,                       -- the data points behind the flag, no free text
  outcome      text check (char_length(outcome) between 3 and 500),
  resolved_by  uuid references public.profiles (id),
  resolved_at  timestamptz,
  created_at   timestamptz not null default now(),
  check ((resolved_at is null) = (outcome is null))
);
create unique index care_flags_one_open on public.care_flags (enrolment_id, reason) where resolved_at is null;

create table public.care_summaries (
  id           uuid primary key default gen_random_uuid(),
  enrolment_id uuid not null references public.care_enrolments (id) on delete cascade,
  week_start   date not null,
  data         jsonb not null,
  summary      text not null,
  created_at   timestamptz not null default now(),
  unique (enrolment_id, week_start)
);

-- One send per enrolment, kind and day, whatever the scanners or the worker retry.
create table private.care_message_log (
  enrolment_id uuid not null references public.care_enrolments (id) on delete cascade,
  kind         text not null,
  day          date not null,
  claimed_at   timestamptz not null default now(),
  primary key (enrolment_id, kind, day)
);

-- Row level security: the patient reads their own; staff read their clinics' patients behind the MFA gate.
do $$
declare t text;
begin
  foreach t in array array['care_enrolments', 'care_thresholds', 'care_checkins', 'aligner_wear', 'care_flags', 'care_summaries'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy staff_need_mfa on public.%I as restrictive for all to authenticated
                    using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()))', t);
    execute format('create trigger audit_row after insert or update or delete on public.%I for each row execute function private.audit_row()', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;
insert into private.audit_redacted_tables (table_name) values ('care_checkins') on conflict do nothing;

create policy read_care_thresholds on public.care_thresholds for select to authenticated using (private.is_staff());
create policy clinician_sets_thresholds on public.care_thresholds for update to authenticated
  using (private.my_role() in ('clinician', 'location_manager', 'org_admin'));
grant update (value) on public.care_thresholds to authenticated;

create policy patient_reads_own_enrolments on public.care_enrolments for select to authenticated
  using (patient_id in (select private.my_patient_ids()));
create policy staff_reads_enrolments on public.care_enrolments for select to authenticated
  using (private.is_staff() and private.can_see_patient(patient_id));
create policy staff_invites on public.care_enrolments for insert to authenticated
  with check (private.is_staff() and private.can_see_patient(patient_id) and status = 'invited' and consent_at is null);
grant insert (id, patient_id, location_id, programme, appointment_id, starts_on, ends_on, wear_target_hours, created_by)
  on public.care_enrolments to authenticated;

create policy patient_reads_own_checkins on public.care_checkins for select to authenticated
  using (patient_id in (select private.my_clinical_patient_ids()));
create policy staff_reads_care_checkins on public.care_checkins for select to authenticated
  using (private.is_staff() and private.can_see_patient(patient_id));
create policy patient_reads_own_wear on public.aligner_wear for select to authenticated
  using (patient_id in (select private.my_patient_ids()));
create policy staff_reads_wear on public.aligner_wear for select to authenticated
  using (private.is_staff() and private.can_see_patient(patient_id));
create policy staff_reads_flags on public.care_flags for select to authenticated
  using (private.is_staff() and private.can_see_patient(patient_id));
create policy staff_reads_summaries on public.care_summaries for select to authenticated
  using (private.is_staff() and private.can_see_patient((select e.patient_id from public.care_enrolments e where e.id = enrolment_id)));

alter table public.staff_tasks drop constraint staff_tasks_kind_check,
  add constraint staff_tasks_kind_check check (kind in ('schedule_conflict', 'checkin_follow_up', 'billing_follow_up',
                                                        'shop_fulfilment', 'assistant_handover', 'website_lead', 'care_alert', 'care_flag'));

-- ---------- the patient's side ----------

create function private.my_care_enrolment(enrolment uuid) returns public.care_enrolments
language sql stable security definer set search_path = '' as $$
  select e.* from public.care_enrolments e
   where e.id = my_care_enrolment.enrolment and private.passes_patient_gate()
     and e.patient_id = (select l.patient_id from public.patient_links l where l.profile_id = auth.uid())
$$;

-- Joining records consent; leaving stops every message at once.
create function public.join_care_programme(enrolment uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if (private.my_care_enrolment(enrolment)).id is null then
    raise exception 'not your programme' using errcode = 'insufficient_privilege';
  end if;
  update public.care_enrolments set status = 'active', consent_at = now()
   where id = join_care_programme.enrolment and status = 'invited';
end;
$$;

create function public.leave_care_programme(enrolment uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if (private.my_care_enrolment(enrolment)).id is null then
    raise exception 'not your programme' using errcode = 'insufficient_privilege';
  end if;
  update public.care_enrolments set status = 'withdrawn' where id = leave_care_programme.enrolment and status in ('invited', 'active');
end;
$$;

-- W25: the answer and its level, by fixed rules and the clinician's thresholds. Emergency: a red flag in the note
-- (the W11 patterns: breathing, heavy bleeding, spreading swelling...) or swelling with fever; it opens an urgent task
-- and goes on the urgent queue. Task: pain at the threshold, "worse" after the threshold day, fever, a bad taste.
-- Nudge: anything else that is not getting better after day 3. Returns the level so the app can show the right text.
create function public.answer_care_checkin(checkin uuid, pain integer, feeling text, symptoms text[], note text)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  c   public.care_checkins;
  e   public.care_enrolments;
  day integer;
  flags text[] := private.red_flags(note);
  lvl text;
begin
  select * into c from public.care_checkins x where x.id = answer_care_checkin.checkin;
  e := private.my_care_enrolment(c.enrolment_id);
  if e.id is null or e.status <> 'active' then
    raise exception 'not your check-in' using errcode = 'insufficient_privilege';
  end if;
  if c.answered_at is not null then
    return c.level;   -- answering twice changes nothing
  end if;
  day := c.due_on - e.starts_on + 1;
  lvl := case
    when cardinality(flags) > 0 or (symptoms @> array['swelling'] and symptoms @> array['fever']) then 'emergency'
    when pain >= (select value from public.care_thresholds where programme = 'post_procedure' and rule = 'pain_task')
      or (feeling = 'worse' and day > (select value from public.care_thresholds where programme = 'post_procedure' and rule = 'worse_after_day'))
      or symptoms && array['fever', 'bad_taste'] then 'task'
    when feeling <> 'better' and day > 3 then 'nudge'
    else 'ok' end;
  update public.care_checkins set pain = answer_care_checkin.pain, feeling = answer_care_checkin.feeling,
         symptoms = coalesce(answer_care_checkin.symptoms, '{}'), note = nullif(btrim(answer_care_checkin.note), ''),
         red_flags = flags, level = lvl, answered_at = now()
   where id = c.id;
  if lvl in ('task', 'emergency') then
    insert into public.staff_tasks (kind, location_id, reference_id, priority)
    values ('care_alert', e.location_id, c.id, case when lvl = 'emergency' then 'urgent' else 'high' end);
  end if;
  if lvl = 'emergency' then
    perform pgmq.send('urgent', jsonb_build_object('type', 'care_alert', 'enrolment_id', e.id, 'checkin_id', c.id));
  end if;
  perform private.raise_care_flags(e.id);
  return lvl;
end;
$$;

-- The aligner timer shares one number a day, only while the patient is in the programme.
create function public.record_aligner_wear(enrolment uuid, day date, hours numeric) returns void
language plpgsql security definer set search_path = '' as $$
declare e public.care_enrolments := private.my_care_enrolment(enrolment);
begin
  if e.id is null or e.status <> 'active' or e.programme <> 'aligners' then
    raise exception 'not your aligner programme' using errcode = 'insufficient_privilege';
  end if;
  insert into public.aligner_wear (enrolment_id, patient_id, day, hours) values (e.id, e.patient_id, record_aligner_wear.day, record_aligner_wear.hours)
  on conflict (enrolment_id, day) do update set hours = excluded.hours;
  perform private.raise_care_flags(e.id);
end;
$$;

-- ---------- W28: check-up flags ----------

-- When a clinician last closed a flag of this reason for this enrolment (-infinity if never).
create function private.care_flag_closed(enrolment uuid, reason text) returns timestamptz
language sql stable security definer set search_path = '' as $$
  select coalesce(max(f.resolved_at), '-infinity') from public.care_flags f
   where f.enrolment_id = care_flag_closed.enrolment and f.reason = care_flag_closed.reason
$$;

-- Opens one check-up flag; only a new one (none open for the same reason) becomes a care task and a booking offer.
create function private.open_care_flag(e public.care_enrolments, reason text, data jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare f uuid;
begin
  insert into public.care_flags (enrolment_id, patient_id, reason, data) values (e.id, e.patient_id, open_care_flag.reason, open_care_flag.data)
  on conflict do nothing returning id into f;
  if f is null then return; end if;
  insert into public.staff_tasks (kind, location_id, reference_id, priority) values ('care_flag', e.location_id, f, 'high');
  insert into private.care_message_log (enrolment_id, kind, day) values (e.id, 'offer', current_date) on conflict do nothing;
  if found then
    perform pgmq.send('notifications', jsonb_build_object('type', 'care', 'kind', 'offer', 'enrolment_id', e.id));
  end if;
end;
$$;

-- W28: the rules behind check-up flags, from the data points only.
create function private.raise_care_flags(enrolment uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  e public.care_enrolments;
  short_by numeric := (select value from public.care_thresholds where programme = 'aligners' and rule = 'short_by_hours');
  flag_days numeric := (select value from public.care_thresholds where programme = 'aligners' and rule = 'short_days_flag');
  missed numeric := (select value from public.care_thresholds where programme = 'post_procedure' and rule = 'missed_checkins_flag');
  pains integer[];
  d jsonb;
begin
  select * into e from public.care_enrolments x where x.id = raise_care_flags.enrolment and x.status = 'active';
  if e.id is null then return; end if;
  -- each rule counts only evidence newer than the last flag a clinician closed for the same reason
  if e.programme = 'post_procedure' then
    select jsonb_agg(jsonb_build_object('day', c.due_on, 'symptoms', c.symptoms, 'red_flags', c.red_flags) order by c.due_on) into d
      from public.care_checkins c where c.enrolment_id = e.id and c.level = 'emergency' and c.answered_at > private.care_flag_closed(e.id, 'serious_side_effect');
    if d is not null then
      perform private.open_care_flag(e, 'serious_side_effect', jsonb_build_object('checkins', d));
    end if;
    select array_agg(c.pain order by c.due_on desc) into pains
      from (select x.pain, x.due_on from public.care_checkins x where x.enrolment_id = e.id and x.pain is not null
              and x.answered_at > private.care_flag_closed(e.id, 'worsening_trend') order by x.due_on desc limit 3) c;
    if cardinality(pains) = 3 and pains[1] > pains[2] and pains[2] > pains[3] then
      perform private.open_care_flag(e, 'worsening_trend', jsonb_build_object('pain_last_three_days', pains));
    end if;
    if (select count(*) filter (where last.answered_at is null) from (
          select c.answered_at from public.care_checkins c where c.enrolment_id = e.id and c.due_on < current_date
             and c.due_on > private.care_flag_closed(e.id, 'missed_checkins')::date
           order by c.due_on desc limit missed::int) last) >= missed then
      perform private.open_care_flag(e, 'missed_checkins', jsonb_build_object('missed_in_a_row', missed));
    end if;
  elsif e.programme = 'aligners' then
    select jsonb_agg(jsonb_build_object('day', w.day, 'hours', w.hours) order by w.day) into d
      from public.aligner_wear w where w.enrolment_id = e.id and w.day > current_date - 7;
    if (select count(*) from public.aligner_wear w where w.enrolment_id = e.id and w.day > current_date - 7
          and w.day > private.care_flag_closed(e.id, 'missed_wear')::date
          and w.hours < e.wear_target_hours - short_by) >= flag_days then
      perform private.open_care_flag(e, 'missed_wear', jsonb_build_object('target_hours', e.wear_target_hours, 'last_7_days', d));
    end if;
  end if;
end;
$$;

-- A flag stays open until a clinician records what was done.
create function public.resolve_care_flag(flag uuid, outcome text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not (private.is_staff() and private.has_mfa() and private.my_role() in ('clinician', 'location_manager', 'org_admin')) then
    raise exception 'a clinician records the outcome' using errcode = 'insufficient_privilege';
  end if;
  update public.care_flags f set outcome = btrim(resolve_care_flag.outcome), resolved_by = auth.uid(), resolved_at = now()
   where f.id = resolve_care_flag.flag and f.resolved_at is null and private.can_see_patient(f.patient_id);
  if not found then
    raise exception 'no open flag you can see' using errcode = 'no_data_found';
  end if;
end;
$$;

-- ---------- the scanners ----------

-- Messages only between 09:00 and 20:00 in the clinic's time zone (quiet hours).
create function private.care_awake(location uuid, at timestamptz) returns boolean
language sql stable set search_path = '' as $$
  select (at at time zone l.time_zone)::time between time '09:00' and time '20:00' from public.locations l where l.id = location
$$;

-- W24: at 10:00 clinic time, today's check-in for each active post-procedure enrolment and a recall reminder when it
-- falls due; programmes that have ended are completed.
create function private.claim_due_care(at timestamptz default now()) returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer := 0; r record;
begin
  update public.care_enrolments set status = 'completed'
   where status = 'active' and ends_on < (at at time zone 'America/New_York')::date;
  for r in
    select e.*, (at at time zone l.time_zone) as local_now from public.care_enrolments e join public.locations l on l.id = e.location_id
     where e.status = 'active' and (at at time zone l.time_zone)::date between e.starts_on and e.ends_on
       and (at at time zone l.time_zone)::time >= time '10:00'
  loop
    if r.programme = 'post_procedure' then
      insert into public.care_checkins (enrolment_id, patient_id, due_on) values (r.id, r.patient_id, r.local_now::date)
      on conflict do nothing;
      if found then
        insert into private.care_message_log (enrolment_id, kind, day) values (r.id, 'checkin', r.local_now::date) on conflict do nothing;
        perform pgmq.send('notifications', jsonb_build_object('type', 'care', 'kind', 'checkin', 'enrolment_id', r.id));
        n := n + 1;
      end if;
    elsif r.programme = 'recall' and r.local_now::date = r.ends_on then
      insert into private.care_message_log (enrolment_id, kind, day) values (r.id, 'recall', r.local_now::date) on conflict do nothing;
      if found then
        perform pgmq.send('notifications', jsonb_build_object('type', 'care', 'kind', 'recall', 'enrolment_id', r.id));
        n := n + 1;
      end if;
    end if;
  end loop;
  return n;
end;
$$;
select cron.schedule('care-checkins', '*/10 * * * *', $$ select private.claim_due_care() $$);

-- W27: approved nudges, once a day at most per enrolment, outside quiet hours: a check-in not answered by 18:00, or
-- aligner wear short of the target for the threshold number of days in a row. Also re-checks W28 flags.
create function private.claim_due_nudges(at timestamptz default now()) returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer := 0; r record;
  short_by numeric := (select value from public.care_thresholds where programme = 'aligners' and rule = 'short_by_hours');
  short_days numeric := (select value from public.care_thresholds where programme = 'aligners' and rule = 'short_days_nudge');
begin
  for r in
    select e.*, (at at time zone l.time_zone) as local_now from public.care_enrolments e join public.locations l on l.id = e.location_id
     where e.status = 'active' and private.care_awake(e.location_id, at)
  loop
    perform private.raise_care_flags(r.id);
    if (r.programme = 'post_procedure' and r.local_now::time >= time '18:00'
          and exists (select 1 from public.care_checkins c where c.enrolment_id = r.id and c.due_on = r.local_now::date and c.answered_at is null))
       or (r.programme = 'aligners'
          and (select count(*) from public.aligner_wear w where w.enrolment_id = r.id and w.day >= r.local_now::date - short_days::int
                 and w.day < r.local_now::date and w.hours < r.wear_target_hours - short_by) >= short_days) then
      insert into private.care_message_log (enrolment_id, kind, day) values (r.id, 'nudge', r.local_now::date) on conflict do nothing;
      if found then
        perform pgmq.send('notifications', jsonb_build_object('type', 'care', 'kind', 'nudge', 'enrolment_id', r.id));
        n := n + 1;
      end if;
    end if;
  end loop;
  return n;
end;
$$;
select cron.schedule('care-nudges', '0 * * * *', $$ select private.claim_due_nudges() $$);

-- W26: every Monday, a summary of the last week for the clinician, from the data points only (no model, so nothing in
-- it can be invented; every number comes from a row). Kept with the enrolment and shown in the care worklist.
create function private.write_care_summaries(from_week date default (date_trunc('week', now()) - interval '7 days')::date)
returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer := 0; r record; d jsonb; s text;
begin
  for r in select * from public.care_enrolments where status in ('active', 'completed') and starts_on < from_week + 7 and ends_on >= from_week loop
    if r.programme = 'post_procedure' then
      select jsonb_build_object('due', count(*), 'answered', count(answered_at), 'max_pain', max(pain),
                                'worse', count(*) filter (where feeling = 'worse'), 'alerts', count(*) filter (where level in ('task', 'emergency')),
                                'pain_by_day', coalesce(jsonb_agg(jsonb_build_object('day', due_on, 'pain', pain) order by due_on) filter (where pain is not null), '[]'))
        into d from public.care_checkins where enrolment_id = r.id and due_on between from_week and from_week + 6;
      s := format('Answered %s of %s check-ins. Highest pain %s of 10. %s answers felt worse; %s needed the team.',
                  d->>'answered', d->>'due', coalesce(d->>'max_pain', 'not reported'), d->>'worse', d->>'alerts');
    elsif r.programme = 'aligners' then
      select jsonb_build_object('days_reported', count(*), 'average_hours', round(avg(hours), 1), 'target_hours', r.wear_target_hours,
                                'short_days', count(*) filter (where hours < r.wear_target_hours - 2))
        into d from public.aligner_wear where enrolment_id = r.id and day between from_week and from_week + 6;
      s := format('Wear reported on %s of 7 days, %s hours a day on average against a target of %s; %s short days.',
                  d->>'days_reported', coalesce(d->>'average_hours', '0'), d->>'target_hours', d->>'short_days');
    else
      continue;
    end if;
    insert into public.care_summaries (enrolment_id, week_start, data, summary) values (r.id, from_week, d, s)
    on conflict (enrolment_id, week_start) do update set data = excluded.data, summary = excluded.summary;
    n := n + 1;
  end loop;
  return n;
end;
$$;
select cron.schedule('care-summaries', '0 11 * * 1', $$ select private.write_care_summaries() $$);

-- What the worker needs to write a care message: IDs in, the minimum out.
create function private.care_context(enrolment uuid)
returns table (patient_id uuid, first_name text, email text, programme text, status text, clinic_name text, clinic_phone text,
               ends_on date, wear_target_hours numeric)
language sql stable security definer set search_path = '' as $$
  select p.id, coalesce(p.preferred_name, p.given_name), u.email::text, e.programme, e.status, l.name, l.phone, e.ends_on, e.wear_target_hours
    from public.care_enrolments e
    join public.patients p on p.id = e.patient_id
    join public.locations l on l.id = e.location_id
    left join public.patient_links pl on pl.patient_id = p.id
    left join auth.users u on u.id = pl.profile_id
   where e.id = care_context.enrolment
$$;

revoke all on function private.my_care_enrolment(uuid), public.join_care_programme(uuid), public.leave_care_programme(uuid),
  public.answer_care_checkin(uuid, integer, text, text[], text), public.record_aligner_wear(uuid, date, numeric),
  private.care_flag_closed(uuid, text), private.open_care_flag(public.care_enrolments, text, jsonb), private.raise_care_flags(uuid), public.resolve_care_flag(uuid, text), private.care_awake(uuid, timestamptz),
  private.claim_due_care(timestamptz), private.claim_due_nudges(timestamptz), private.write_care_summaries(date),
  private.care_context(uuid) from public;
grant execute on function public.join_care_programme(uuid), public.leave_care_programme(uuid),
  public.answer_care_checkin(uuid, integer, text, text[], text), public.record_aligner_wear(uuid, date, numeric),
  public.resolve_care_flag(uuid, text) to authenticated;
grant execute on function private.care_context(uuid) to northgate_worker;
