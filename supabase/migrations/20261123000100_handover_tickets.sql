-- Team requests in Jira (ADR 0013). n8n turns each assistant handover into one Jira ticket in project NGD.
-- Line-by-line review (Fiona): what leaves the database for a vendor without a BAA.
--
-- n8n (role northgate_patient_actions) never reads assistant_handovers. It calls claim_handover_tickets, which returns
-- only the allow-listed fields, and record_handover_ticket, which stores the Jira key. A claim without a key is offered
-- again after 10 minutes, so a failed Jira call is retried; the primary key makes a second ticket impossible.
create table private.handover_tickets (
  handover_id uuid primary key references public.assistant_handovers (id) on delete cascade,
  jira_key    text check (jira_key ~ '^[A-Z][A-Z0-9]+-[0-9]+$'),
  claimed_at  timestamptz not null default now()
);

create function private.claim_handover_tickets(max_rows integer default 10)
returns table (handover_id uuid, short_ref text, category text, clinic text, created_at timestamptz)
language sql security definer set search_path = '' as $$
  with todo as (
    select h.id
    from public.assistant_handovers h
    left join private.handover_tickets t on t.handover_id = h.id
    where t.handover_id is null or (t.jira_key is null and t.claimed_at < now() - interval '10 minutes')
    order by h.created_at
    limit least(greatest(max_rows, 1), 50)
  ), claimed as (
    insert into private.handover_tickets (handover_id) select id from todo
    on conflict (handover_id) do update set claimed_at = now()
      where private.handover_tickets.jira_key is null
        and private.handover_tickets.claimed_at < now() - interval '10 minutes'
    returning private.handover_tickets.handover_id
  )
  select h.id, left(h.id::text, 8), h.category, l.name, h.created_at
  from claimed c
  join public.assistant_handovers h on h.id = c.handover_id
  join public.patients p on p.id = h.patient_id
  join public.locations l on l.id = p.home_location_id;
$$;

create function private.record_handover_ticket(handover uuid, key text) returns void
language sql security definer set search_path = '' as $$
  update private.handover_tickets set jira_key = key where handover_id = handover;
$$;

revoke all on function private.claim_handover_tickets(integer), private.record_handover_ticket(uuid, text) from public;
grant execute on function private.claim_handover_tickets(integer), private.record_handover_ticket(uuid, text)
  to northgate_patient_actions;
