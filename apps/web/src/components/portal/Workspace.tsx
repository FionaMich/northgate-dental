"use client";
// The Northgate clinical workspace for staff. Every page reads through the database client in DbContext: the real
// portal passes the Supabase client (row level security decides the rows, two-factor is required), the public demo
// passes demoDb (sample data made in the browser). Times are shown in Boston time, where the clinics are.
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import Logo from "@/components/Logo";
import { supabase } from "@/lib/supabase";
import { money } from "@/lib/data";

export const DbContext = createContext<SupabaseClient>(supabase);
const useDb = () => useContext(DbContext);

type Row = Record<string, unknown>;
type Me = { id: string; role: string; display_name: string };

// A clinical system's look: square corners, hairline rules, dense tables, one accent colour used sparingly.
export const input = "mt-1 w-full rounded-md border border-line px-3 py-2.5 outline-none focus:border-teal focus:ring-2 focus:ring-enamel";
const panel = "rounded-md border border-[#dde3e2] bg-white";
const button = "rounded-md bg-teal px-3.5 py-1.5 text-[13px] font-semibold text-white transition hover:bg-teal-dark disabled:opacity-60";
const ghost = "rounded-md border border-[#cfd8d6] bg-white px-3 py-1.5 text-[13px] font-semibold text-sea transition hover:bg-[#f2f6f5]";
const th = "px-4 py-2 text-[11px] font-semibold text-muted";
const td = "px-4 py-2";
const TZ = "America/New_York";
const time = (iso: unknown) => new Date(String(iso)).toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: TZ });
const when = (iso: unknown) => new Date(String(iso)).toLocaleString("en-US", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", hour12: false, timeZone: TZ });
const minutesInBoston = (iso: unknown) => { const [h, m] = time(iso).split(":").map(Number); return h * 60 + m; };
const person = (p: unknown) => (p ? `${String((p as Row).given_name)} ${String((p as Row).family_name)}` : "Not linked");
const initials = (name: string) => name.replace(/^Dr /, "").split(/[\s,]+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join("").toUpperCase();
const clean = (name: unknown) => String(name ?? "").replace(/ \(.*\)$/, "");
const dayStart = (d: Date) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };

const ROLE: Record<string, string> = { receptionist: "Front desk", clinician: "Clinician", location_manager: "Clinic manager", org_admin: "Practice manager" };
const STATUS: Record<string, { label: string; bar: string; bg: string }> = {
  completed: { label: "Completed", bar: "border-l-[#9aa9a7]", bg: "bg-[#f4f6f6] text-muted" },
  checked_in: { label: "In the chair", bar: "border-l-shine", bg: "bg-[#e8f8f3] text-sea" },
  booked: { label: "Booked", bar: "border-l-teal", bg: "bg-white text-sea" },
  no_show: { label: "No-show", bar: "border-l-danger", bg: "bg-[#fdf0ef] text-danger" },
};
const KIND: Record<string, string> = {
  assistant_handover: "Passed on by Nora", website_lead: "Website question", schedule_conflict: "Schedule conflict",
  checkin_follow_up: "Check-in follow-up", billing_follow_up: "Billing follow-up", shop_fulfilment: "Shop order",
  care_alert: "Care check-in needs a clinician", care_flag: "Check-up flag",
};
const CATEGORY: Record<string, string> = {
  booking: "Booking", billing: "Billing", clinical_question: "Clinical question", shop: "Shop", other: "Other", emergency: "Emergency",
};

// ---------------------------------------------------------------------------------------------------- data hooks

function useRows(load: () => PromiseLike<{ data: unknown; error: { message: string } | null }>, deps: unknown[] = []) {
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState("");
  const reload = useCallback(() => {
    void load().then(({ data, error }) => { setError(error ? "This list is not available for your account." : ""); setRows((data as Row[] | null) ?? []); });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  useEffect(reload, [reload]);
  return { rows, error, reload };
}

function useDay(day: Date) {
  const db = useDb();
  const next = new Date(day); next.setDate(next.getDate() + 1);
  return useRows(() => db.from("appointments")
    .select("id, starts_at, ends_at, status, patients(given_name, family_name, mrn), services(name), practitioners(display_name, profile_id), locations(name)")
    .gte("starts_at", day.toISOString()).lt("starts_at", next.toISOString()).neq("status", "cancelled").order("starts_at") as never, [db, day.getTime()]);
}

// ---------------------------------------------------------------------------------------------------- small pieces

const ICONS: Record<string, string> = {
  Overview: "M4 5h6v6H4zM14 5h6v4h-6zM14 13h6v6h-6zM4 15h6v4H4z",
  Schedule: "M7 3v3M17 3v3M4 8h16M5 5h14v15H5z",
  Patients: "M16 19v-1a4 4 0 0 0-8 0v1M12 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6",
  "Dentist desk": "M12 3c-3 0-5 1.5-5 4.5 0 3 1 5 1.5 8.5.3 2 1 4 2 4s1-3 1.5-3 .5 3 1.5 3 1.7-2 2-4C17 12.5 18 10.5 18 7.5 18 4.5 15 3 12 3z",
  Inbox: "M4 13h4l2 3h4l2-3h4M5 5h14l1 8v6H4v-6z",
  Coverage: "M4 7h16v11H4zM4 11h16M8 15h3",
  Roster: "M8 7V3M16 7V3M4 9h16M5 5h14v15H5zM8 13h2M8 16h6",
  Payments: "M3 7h18v10H3zM3 11h18M7 15h2",
  "Nora activity": "M4 18V9M10 18V5M16 18v-6M22 18H2",
  Settings: "M4 7h10M18 7h2M4 17h4M12 17h8M14 5v4M8 15v4",
  Care: "M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z",
  Search: "M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM20 20l-4-4",
};
function Icon({ name, className = "size-[18px]" }: { name: string; className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d={ICONS[name] ?? ICONS.Overview} />
    </svg>
  );
}

function Avatar({ name, dark = false }: { name: string; dark?: boolean }) {
  return <span aria-hidden className={`grid size-7 shrink-0 place-items-center rounded-full text-[10px] font-bold ${dark ? "bg-white/15 text-white" : "bg-[#e5eeec] text-teal-dark"}`}>{initials(name)}</span>;
}

const TAG: Record<string, string> = {
  teal: "border-teal/30 bg-[#eef7f5] text-teal-dark", grey: "border-[#d6dedc] bg-[#f5f7f7] text-muted",
  amber: "border-[#f0cfa8] bg-[#fdf5ec] text-[#8a4b14]", red: "border-danger/30 bg-[#fdf0ef] text-danger",
};
function Tag({ children, tone = "teal" }: { children: React.ReactNode; tone?: keyof typeof TAG }) {
  return <span className={`inline-flex items-center rounded-sm border px-1.5 py-px text-[11px] font-semibold ${TAG[tone]}`}>{children}</span>;
}

function Figures({ items }: { items: [string, React.ReactNode, string?, string?][] }) {
  return (
    <div className={`${panel} grid grid-cols-2 divide-[#e6ebea] sm:grid-cols-3 xl:grid-flow-col xl:auto-cols-fr xl:grid-cols-none xl:divide-x`}>
      {items.map(([label, value, note, tone]) => (
        <div key={label} className="px-4 py-3">
          <p className="text-[11px] font-semibold text-muted">{label}</p>
          <p className={`mt-0.5 text-2xl font-bold tabular-nums ${tone ?? "text-sea"}`}>{value}</p>
          {note && <p className="text-[11px] text-muted">{note}</p>}
        </div>
      ))}
    </div>
  );
}

function Section({ title, action, children, flush = false }: { title: string; action?: React.ReactNode; children: React.ReactNode; flush?: boolean }) {
  return (
    <section className={panel}>
      <header className="flex items-center justify-between border-b border-[#e6ebea] px-4 py-2.5">
        <h2 className="text-[13px] font-bold">{title}</h2>
        {action}
      </header>
      <div className={flush ? "" : "p-4"}>{children}</div>
    </section>
  );
}

const linkish = "text-[12px] font-semibold text-teal hover:underline";

function State({ rows, error, empty }: { rows: Row[] | null; error: string; empty: string }) {
  if (rows === null) return <p className="px-4 py-6 text-[13px] text-muted">Loading…</p>;
  if (error) return <p className="px-4 py-6 text-[13px] text-muted">{error}</p>;
  if (!rows.length) return <p className="px-4 py-6 text-[13px] text-muted">{empty}</p>;
  return null;
}

// ---------------------------------------------------------------------------------------------------- the shell

const NAV = ["Overview", "Schedule", "Patients", "Care", "Dentist desk", "Inbox", "Coverage", "Roster", "Payments", "Nora activity", "Settings"] as const;
type Page = (typeof NAV)[number];

export function Workspace({ onSignOut }: { onSignOut: () => void }) {
  const db = useDb();
  const [page, setPage] = useState<Page>("Overview");
  const [me, setMe] = useState<Me | null>(null);
  const [clinic, setClinic] = useState("All clinics");
  const [query, setQuery] = useState("");
  const tasks = useRows(() => db.from("staff_tasks").select("id").is("done_at", null) as never, [db, page]);
  const cards = useRows(() => db.from("coverages").select("id, status").eq("status", "pending_review") as never, [db, page]);
  const org = useRows(() => db.from("org_settings").select("settings") as never, [db, page]);
  const noraOn = ((org.rows?.[0]?.settings ?? {}) as Row).assistant_enabled !== false;
  useEffect(() => {
    void db.auth.getUser().then(async ({ data: { user } }) => {
      const { data } = await db.from("profiles").select("id, role, display_name").eq("id", user?.id ?? "").maybeSingle();
      setMe((data as Me | null) ?? null);
    });
  }, [db]);
  const flags = useRows(() => db.from("care_flags").select("id").is("resolved_at", null) as never, [db, page]);
  const badge: Partial<Record<Page, number>> = { Inbox: tasks.rows?.length, Coverage: cards.rows?.length, Care: flags.rows?.length };
  const today = new Date().toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", year: "numeric", timeZone: TZ });
  const go = (p: Page) => { setPage(p); window.scrollTo({ top: 0 }); };

  return (
    <div className="min-h-screen text-[13px] text-sea">
      <header className="sticky top-0 z-30 border-b border-black/20 bg-sea text-white">
        <div className="flex h-12 items-center gap-4 px-4">
          <div className="flex items-center gap-2.5 pr-2 lg:w-52">
            <Logo className="size-6" />
            <p className="text-[13px] font-bold">Northgate <span className="font-normal text-white/60">Workspace</span></p>
          </div>
          <label className="hidden md:block">
            <span className="sr-only">Clinic</span>
            <select value={clinic} onChange={(e) => setClinic(e.target.value)}
              className="rounded-md border border-white/20 bg-transparent px-2 py-1 text-[13px] font-semibold focus:outline-none [&>option]:text-sea">
              {["All clinics", "Back Bay", "Cambridge", "Quincy"].map((c) => <option key={c}>{c}</option>)}
            </select>
          </label>
          <label className="relative hidden flex-1 md:block md:max-w-sm">
            <span className="sr-only">Find a patient</span>
            <Icon name="Search" className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-white/50" />
            <input value={query} onChange={(e) => { setQuery(e.target.value); if (page !== "Patients") go("Patients"); }}
              placeholder="Patient name or record number"
              className="w-full rounded-md border border-white/20 bg-white/5 py-1 pl-8 pr-3 text-[13px] placeholder:text-white/45 focus:bg-white focus:text-sea focus:outline-none" />
          </label>
          <div className="ml-auto flex items-center gap-4">
            <span className="hidden tabular-nums text-white/60 lg:block">{today}</span>
            <button onClick={() => go("Settings")} className="hidden items-center gap-1.5 text-[12px] font-semibold sm:flex" title="Nora, the AI receptionist">
              <span className={`size-2 rounded-full ${noraOn ? "bg-shine" : "bg-danger"}`} />Nora {noraOn ? "on" : "off"}
            </button>
            <div className="flex items-center gap-2 border-l border-white/15 pl-4">
              <Avatar name={me?.display_name ?? "Staff"} dark />
              <div className="hidden leading-tight sm:block">
                <p className="text-[12px] font-semibold">{me?.display_name ?? "Signed in"}</p>
                <p className="text-[11px] text-white/55">{ROLE[me?.role ?? ""] ?? ""}</p>
              </div>
            </div>
            <button onClick={onSignOut} className="text-[12px] text-white/60 hover:text-white">Sign out</button>
          </div>
        </div>
      </header>

      <div className="flex">
        <nav aria-label="Workspace" className="sticky top-12 hidden h-[calc(100vh-3rem)] w-56 shrink-0 flex-col border-r border-[#dde3e2] bg-white py-3 lg:flex">
          {NAV.map((p) => (
            <button key={p} onClick={() => go(p)} aria-current={page === p ? "page" : undefined}
              className={`flex items-center gap-3 border-l-2 py-2 pl-4 pr-3 text-left text-[13px] transition ${page === p ? "border-l-teal bg-[#eef5f3] font-semibold text-teal-dark" : "border-l-transparent text-sea/75 hover:bg-[#f5f8f7] hover:text-sea"}`}>
              <Icon name={p} />
              <span className="flex-1">{p}</span>
              {!!badge[p] && <span className="min-w-5 rounded-sm bg-sea px-1 text-center text-[10px] font-bold leading-4 text-white">{badge[p]}</span>}
            </button>
          ))}
          <p className="mt-auto border-t border-[#e6ebea] px-4 pt-3 text-[11px] leading-4 text-muted">Two-factor session. Every change is written to the audit log.</p>
        </nav>

        <div className="min-w-0 flex-1 px-4 py-5 sm:px-6">
          <div className="mb-4 flex gap-1.5 overflow-x-auto pb-1 lg:hidden">
            {NAV.map((p) => (
              <button key={p} onClick={() => go(p)} className={`shrink-0 rounded-md border px-2.5 py-1 text-[12px] font-semibold ${page === p ? "border-sea bg-sea text-white" : "border-[#cfd8d6] bg-white"}`}>{p}</button>
            ))}
          </div>
          <div className="mb-4 flex items-baseline gap-3 border-b border-[#dde3e2] pb-3">
            <h1 className="text-xl font-bold">{page}</h1>
            <p className="text-[12px] text-muted">{clinic}</p>
          </div>
          {page === "Overview" && <Overview clinic={clinic} go={go} />}
          {page === "Schedule" && <Schedule clinic={clinic} />}
          {page === "Patients" && <Patients clinic={clinic} query={query} setQuery={setQuery} />}
          {page === "Care" && <Care clinic={clinic} />}
          {page === "Dentist desk" && <DentistDesk />}
          {page === "Inbox" && <Inbox clinic={clinic} />}
          {page === "Coverage" && <Coverage />}
          {page === "Roster" && <Roster clinic={clinic} />}
          {page === "Payments" && <Payments />}
          {page === "Nora activity" && <NoraActivity />}
          {page === "Settings" && <Settings me={me} onChange={org.reload} />}
        </div>
      </div>
    </div>
  );
}

const inClinic = (clinic: string, row: Row) => clinic === "All clinics" || (row.locations as Row | null)?.name === clinic;

// ---------------------------------------------------------------------------------------------------- Overview

function Overview({ clinic, go }: { clinic: string; go: (p: Page) => void }) {
  const db = useDb();
  const day = useMemo(() => dayStart(new Date()), []);
  const visits = useDay(day);
  const tasks = useRows(() => db.from("staff_tasks").select("id, kind, priority, created_at, locations(name)").is("done_at", null).order("created_at", { ascending: false }) as never, [db]);
  const cards = useRows(() => db.from("coverages").select("id").eq("status", "pending_review") as never, [db]);
  const pay = useRows(() => db.from("payments").select("amount_cents, status, paid_at").order("created_at", { ascending: false }).limit(200) as never, [db]);
  const nora = useRows(() => db.from("ai_events").select("outcome, latency_ms, created_at").order("created_at", { ascending: false }).limit(200) as never, [db]);

  const v = (visits.rows ?? []).filter((r) => inClinic(clinic, r));
  const now = minutesInBoston(new Date().toISOString());
  const upcoming = v.filter((r) => r.status === "booked" && minutesInBoston(r.starts_at) >= now).slice(0, 8);
  const todayIso = new Date().toLocaleDateString("en-CA", { timeZone: TZ });
  const isToday = (iso: unknown) => !!iso && new Date(String(iso)).toLocaleDateString("en-CA", { timeZone: TZ }) === todayIso;
  const paidToday = (pay.rows ?? []).filter((p) => p.status === "paid" && isToday(p.paid_at));
  const noraToday = (nora.rows ?? []).filter((e) => isToday(e.created_at));
  const latencies = noraToday.map((e) => Number(e.latency_ms)).sort((a, b) => a - b);
  const openTasks = (tasks.rows ?? []).filter((t) => inClinic(clinic, t));
  const urgent = openTasks.filter((t) => t.priority === "urgent").length;
  const byClinic = ["Back Bay", "Cambridge", "Quincy"].map((name) => {
    const list = (visits.rows ?? []).filter((r) => (r.locations as Row | null)?.name === name);
    const booked = list.reduce((s, r) => s + (minutesInBoston(r.ends_at) - minutesInBoston(r.starts_at)), 0);
    const chairs = { "Back Bay": 4, Cambridge: 3, Quincy: 2 }[name] ?? 2;
    return { name, count: list.length, share: Math.min(100, Math.round((booked / (chairs * 9 * 60)) * 100)) };
  });

  return (
    <div className="space-y-4">
      <Figures items={[
        ["Visits today", v.length, upcoming.length ? `next at ${time(upcoming[0].starts_at)}` : "none still to come"],
        ["In the chair", v.filter((r) => r.status === "checked_in").length],
        ["Completed", v.filter((r) => r.status === "completed").length],
        ["Open tasks", openTasks.length, urgent ? `${urgent} urgent` : "none urgent", urgent ? "text-danger" : undefined],
        ["Cards to verify", cards.rows?.length ?? "…"],
        ["Collected today", money(paidToday.reduce((s, p) => s + Number(p.amount_cents), 0)), `${paidToday.length} payments`],
      ]} />

      <div className="grid gap-4 xl:grid-cols-[1.5fr_1fr]">
        <Section title="Coming up today" action={<button onClick={() => go("Schedule")} className={linkish}>Schedule</button>} flush>
          {!upcoming.length ? <p className="px-4 py-6 text-muted">Nobody else is booked today.</p> : (
            <table className="w-full text-left">
              <thead className="border-b border-[#eef1f0]"><tr><th className={th}>Time</th><th className={th}>Patient</th><th className={th}>Visit</th><th className={th}>With</th><th className={th}>Clinic</th></tr></thead>
              <tbody className="divide-y divide-[#eef1f0]">
                {upcoming.map((r) => (
                  <tr key={String(r.id)}>
                    <td className={`${td} font-semibold tabular-nums text-teal-dark`}>{time(r.starts_at)}</td>
                    <td className={td}><p className="whitespace-nowrap font-semibold">{person(r.patients)}</p><p className="font-mono text-[11px] text-muted">{String((r.patients as Row | null)?.mrn ?? "")}</p></td>
                    <td className={td}>{String((r.services as Row | null)?.name ?? "")}</td>
                    <td className={td}>{clean((r.practitioners as Row | null)?.display_name)}</td>
                    <td className={`${td} text-muted`}>{String((r.locations as Row | null)?.name ?? "")}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Section>

        <Section title="Needs attention" action={<button onClick={() => go("Inbox")} className={linkish}>Inbox</button>} flush>
          {!openTasks.length ? <p className="px-4 py-6 text-muted">Nothing waiting.</p> : (
            <ul className="divide-y divide-[#eef1f0]">
              {openTasks.slice(0, 7).map((t) => (
                <li key={String(t.id)} className="flex items-center gap-3 px-4 py-2">
                  <Tag tone={t.priority === "urgent" ? "red" : t.priority === "high" ? "amber" : "grey"}>{String(t.priority)}</Tag>
                  <p className="flex-1 truncate">{KIND[String(t.kind)] ?? String(t.kind)} <span className="text-muted">· {String((t.locations as Row | null)?.name ?? "")}</span></p>
                  <span className="tabular-nums text-[12px] text-muted">{time(t.created_at)}</span>
                </li>
              ))}
            </ul>
          )}
        </Section>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Section title="Chair time booked today">
          <table className="w-full text-left">
            <tbody>
              {byClinic.map((c) => (
                <tr key={c.name}>
                  <td className="w-28 py-2 font-semibold">{c.name}</td>
                  <td className="py-2"><div className="h-2 bg-[#edf2f1]"><div className="h-2 bg-teal" style={{ width: `${c.share}%` }} /></div></td>
                  <td className="w-36 py-2 text-right tabular-nums text-muted">{c.share}% · {c.count} visits</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Section>
        <Section title="Nora today" action={<button onClick={() => go("Nora activity")} className={linkish}>Activity</button>}>
          <dl className="grid grid-cols-3 divide-x divide-[#eef1f0]">
            {[["Turns", noraToday.length], ["Passed to the team", noraToday.filter((e) => e.outcome === "handover").length],
              ["Median reply", latencies.length ? `${(latencies[Math.floor(latencies.length / 2)] / 1000).toFixed(0)} s` : "–"]].map(([k, val]) => (
              <div key={String(k)} className="px-3 first:pl-0"><dt className="text-[11px] text-muted">{k}</dt><dd className="text-xl font-bold tabular-nums">{val}</dd></div>
            ))}
          </dl>
          <p className="mt-3 text-[11px] text-muted">Counts only. The activity log never holds what anyone said.</p>
        </Section>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------- Schedule

const OPEN = 7 * 60, CLOSE = 20 * 60, PX = 1.25;   // the grid runs 07:00 to 20:00

function Schedule({ clinic }: { clinic: string }) {
  const [day, setDay] = useState(() => dayStart(new Date()));
  const visits = useDay(day);
  const move = (n: number) => setDay((d) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; });
  const rows = (visits.rows ?? []).filter((r) => inClinic(clinic, r));
  const columns = new Map<string, Row[]>();
  for (const v of rows) {
    const who = clean((v.practitioners as Row | null)?.display_name) || "Unassigned";
    columns.set(who, [...(columns.get(who) ?? []), v]);
  }
  const isToday = dayStart(new Date()).getTime() === day.getTime();
  const now = minutesInBoston(new Date().toISOString());

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex">
          <button onClick={() => move(-1)} className={`${ghost} rounded-r-none`} aria-label="Previous day">‹</button>
          <button onClick={() => setDay(dayStart(new Date()))} className={`${ghost} -ml-px rounded-none`}>Today</button>
          <button onClick={() => move(1)} className={`${ghost} -ml-px rounded-l-none`} aria-label="Next day">›</button>
        </div>
        <p className="ml-2 text-[15px] font-bold">{day.toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" })}</p>
        <p className="text-muted">{rows.length} visits</p>
        <div className="ml-auto flex flex-wrap gap-4 text-[12px] text-muted">
          {Object.values(STATUS).map((s) => <span key={s.label} className="flex items-center gap-1.5"><span className={`h-3 w-1 border-l-[3px] ${s.bar}`} />{s.label}</span>)}
        </div>
      </div>
      {visits.rows === null || visits.error || !rows.length ? (
        <div className={panel}><State rows={visits.rows === null ? null : rows} error={visits.error} empty="No visits booked on this day." /></div>
      ) : (
        <div className={`${panel} overflow-x-auto`}>
          <div className="flex min-w-max">
            <div className="sticky left-0 z-10 w-14 shrink-0 border-r border-[#e6ebea] bg-white">
              <div className="h-11 border-b border-[#e6ebea]" />
              <div className="relative" style={{ height: (CLOSE - OPEN) * PX }}>
                {Array.from({ length: (CLOSE - OPEN) / 60 }, (_, i) => (
                  <span key={i} className="absolute right-2 -translate-y-1.5 text-[10px] tabular-nums text-muted" style={{ top: i * 60 * PX }}>{String(7 + i).padStart(2, "0")}:00</span>
                ))}
              </div>
            </div>
            {[...columns.entries()].map(([who, list]) => (
              <div key={who} className="w-52 shrink-0 border-r border-[#eef1f0] last:border-r-0">
                <div className="flex h-11 items-center gap-2 border-b border-[#e6ebea] px-3">
                  <Avatar name={who} />
                  <div className="min-w-0 leading-tight"><p className="truncate font-semibold">{who}</p><p className="text-[11px] text-muted">{String((list[0]?.locations as Row | null)?.name ?? "")} · {list.length}</p></div>
                </div>
                <div className="relative" style={{ height: (CLOSE - OPEN) * PX, backgroundImage: `repeating-linear-gradient(to bottom, #edf1f0 0 1px, transparent 1px ${30 * PX}px)` }}>
                  {list.map((v) => {
                    const start = minutesInBoston(v.starts_at), end = minutesInBoston(v.ends_at);
                    const s = STATUS[String(v.status)] ?? STATUS.booked;
                    return (
                      <div key={String(v.id)} title={`${time(v.starts_at)} to ${time(v.ends_at)}: ${person(v.patients)}, ${String((v.services as Row | null)?.name ?? "")}`}
                        className={`absolute inset-x-1 overflow-hidden border border-l-[3px] border-[#d9e2e0] px-1.5 py-0.5 ${s.bar} ${s.bg}`}
                        style={{ top: (start - OPEN) * PX + 1, height: Math.max((end - start) * PX - 2, 20) }}>
                        <p className="truncate text-[11px] font-semibold"><span className="tabular-nums">{time(v.starts_at)}</span> {person(v.patients)}</p>
                        <p className="truncate text-[11px] opacity-75">{String((v.services as Row | null)?.name ?? "")}</p>
                      </div>
                    );
                  })}
                  {isToday && now > OPEN && now < CLOSE && <div aria-hidden className="absolute inset-x-0 z-10 border-t border-danger" style={{ top: (now - OPEN) * PX }} />}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------- Patients

const age = (dob: unknown) => {
  if (!dob) return "";
  const d = new Date(String(dob)), n = new Date();
  return String(n.getFullYear() - d.getFullYear() - (n < new Date(n.getFullYear(), d.getMonth(), d.getDate()) ? 1 : 0));
};
const LANG: Record<string, string> = { en: "English", es: "Spanish", fr: "French", nl: "Dutch", de: "German", it: "Italian", lt: "Lithuanian", sv: "Swedish", pt: "Portuguese", zh: "Chinese" };

function Patients({ clinic, query, setQuery }: { clinic: string; query: string; setQuery: (q: string) => void }) {
  const db = useDb();
  const list = useRows(() => db.from("patients").select("id, mrn, given_name, family_name, date_of_birth, preferred_language, locations(name)")
    .order("family_name").limit(300) as never, [db]);
  const q = query.trim().toLowerCase();
  const rows = (list.rows ?? []).filter((p) => inClinic(clinic, p))
    .filter((p) => !q || `${p.given_name} ${p.family_name} ${p.mrn}`.toLowerCase().includes(q));
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-3">
        <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Name or record number" aria-label="Find a patient"
          className="w-full max-w-xs rounded-md border border-[#cfd8d6] bg-white px-3 py-1.5 outline-none focus:border-teal focus:ring-2 focus:ring-enamel" />
        <p className="text-muted">{rows.length} of {list.rows?.length ?? 0}</p>
      </div>
      <div className={`${panel} overflow-x-auto`}>
        {list.rows === null || list.error || !rows.length ? <State rows={list.rows === null ? null : rows} error={list.error} empty="No patient matches." /> : (
          <table className="w-full min-w-[860px] text-left">
            <thead className="border-b border-[#e6ebea] bg-[#f8faf9]">
              <tr>{["Patient", "Record", "Age", "Language", "Home clinic", "Next visit", "Insurance", "Balance"].map((h) => <th key={h} className={th}>{h}</th>)}</tr>
            </thead>
            <tbody className="divide-y divide-[#eef1f0]">
              {rows.map((p) => (
                <tr key={String(p.id)} className="hover:bg-[#f7faf9]">
                  <td className={td}><div className="flex items-center gap-2.5"><Avatar name={person(p)} /><span className="font-semibold">{person(p)}</span></div></td>
                  <td className={`${td} font-mono text-[12px] text-muted`}>{String(p.mrn ?? "")}</td>
                  <td className={`${td} tabular-nums`}>{age(p.date_of_birth)}</td>
                  <td className={td}>{LANG[String(p.preferred_language)] ?? String(p.preferred_language ?? "")}</td>
                  <td className={td}>{String((p.locations as Row | null)?.name ?? "")}</td>
                  <td className={`${td} tabular-nums`}>{p.next_visit ? when(p.next_visit) : <span className="text-muted">None booked</span>}</td>
                  <td className={td}>{p.insurance ? <Tag tone={p.insurance === "Verified" ? "teal" : p.insurance === "Self-pay" ? "grey" : "amber"}>{String(p.insurance)}</Tag> : <span className="text-muted">On file</span>}</td>
                  <td className={`${td} tabular-nums ${Number(p.balance_cents) > 0 ? "font-semibold text-danger" : ""}`}>{p.balance_cents != null ? money(Number(p.balance_cents)) : <span className="text-muted">See Payments</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------- Dentist desk

function DentistDesk() {
  const db = useDb();
  const [me, setMe] = useState<string | null>(null);
  const [viewAs, setViewAs] = useState("");
  const day = useMemo(() => dayStart(new Date()), []);
  const visits = useDay(day);
  useEffect(() => { void db.auth.getUser().then(({ data: { user } }) => setMe(user?.id ?? "")); }, [db]);
  const dentists = [...new Set((visits.rows ?? []).map((v) => clean((v.practitioners as Row | null)?.display_name)))].sort();
  const own = (visits.rows ?? []).filter((v) => (v.practitioners as Row | null)?.profile_id === me);
  // a clinician sees their own day; anyone else (a manager, the front desk) picks whose day to look at
  const who = own.length ? "" : viewAs || dentists[0] || "";
  const mine = visits.rows === null || me === null ? null
    : own.length ? own : (visits.rows ?? []).filter((v) => clean((v.practitioners as Row | null)?.display_name) === who);
  return (
    <div className="space-y-3">
    {!own.length && dentists.length > 0 && (
      <label className="flex items-center gap-2 text-muted">Viewing
        <select value={who} onChange={(e) => setViewAs(e.target.value)} className="rounded-md border border-[#cfd8d6] bg-white px-2 py-1.5 font-semibold text-sea">
          {dentists.map((d) => <option key={d}>{d}</option>)}
        </select>
      </label>
    )}
    <div className={`${panel} overflow-x-auto`}>
      {mine === null || !mine.length ? <State rows={mine} error={visits.error} empty="No patients booked with you today." /> : (
        <table className="w-full min-w-[640px] text-left">
          <thead className="border-b border-[#e6ebea] bg-[#f8faf9]"><tr>{["Time", "Patient", "Record", "Visit", "Clinic", "Status"].map((h) => <th key={h} className={th}>{h}</th>)}</tr></thead>
          <tbody className="divide-y divide-[#eef1f0]">
            {mine.map((v) => {
              const s = STATUS[String(v.status)] ?? STATUS.booked;
              return (
                <tr key={String(v.id)}>
                  <td className={`${td} font-semibold tabular-nums`}>{time(v.starts_at)}–{time(v.ends_at)}</td>
                  <td className={`${td} font-semibold`}>{person(v.patients)}</td>
                  <td className={`${td} font-mono text-[12px] text-muted`}>{String((v.patients as Row | null)?.mrn ?? "")}</td>
                  <td className={td}>{String((v.services as Row | null)?.name ?? "")}</td>
                  <td className={td}>{String((v.locations as Row | null)?.name ?? "")}</td>
                  <td className={td}><Tag tone={v.status === "checked_in" ? "teal" : v.status === "completed" ? "grey" : "teal"}>{s.label}</Tag></td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </div>
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------- Inbox

function Inbox({ clinic }: { clinic: string }) {
  const db = useDb();
  const tasks = useRows(() => db.from("staff_tasks").select("id, kind, priority, reference_id, created_at, locations(name)")
    .is("done_at", null).order("created_at", { ascending: false }).limit(50) as never, [db]);
  const [details, setDetails] = useState<Record<string, Row>>({});
  useEffect(() => {
    const ids = (k: string) => (tasks.rows ?? []).filter((t) => t.kind === k).map((t) => String(t.reference_id));
    void Promise.all([
      db.from("assistant_handovers").select("id, category, language, summary").in("id", ids("assistant_handover")),
      db.from("leads").select("id, name, email, phone, message").in("id", ids("website_lead")),
    ]).then(([h, l]) => setDetails(Object.fromEntries([...(h.data ?? []), ...(l.data ?? [])].map((r) => [String(r.id), r as Row]))));
  }, [tasks.rows, db]);
  async function close(id: unknown) {
    const { data: { user } } = await db.auth.getUser();
    await db.from("staff_tasks").update({ done_at: new Date().toISOString(), done_by: user?.id }).eq("id", String(id));
    tasks.reload();
  }
  const rows = (tasks.rows ?? []).filter((t) => inClinic(clinic, t));
  return (
    <div className={panel}>
      {tasks.rows === null || tasks.error || !rows.length ? <State rows={tasks.rows === null ? null : rows} error={tasks.error} empty="Nothing waiting. New requests from Nora and the website appear here." /> : (
        <ul className="divide-y divide-[#eef1f0]">
          {rows.map((t) => {
            const d = details[String(t.reference_id)];
            return (
              <li key={String(t.id)} className="grid grid-cols-[auto_1fr_auto] items-start gap-4 px-4 py-3">
                <Tag tone={t.priority === "urgent" ? "red" : t.priority === "high" ? "amber" : "grey"}>{String(t.priority)}</Tag>
                <div className="min-w-0">
                  <p><b>{KIND[String(t.kind)] ?? String(t.kind)}</b> <span className="text-muted">· {String((t.locations as Row | null)?.name ?? "")} · <span className="tabular-nums">{when(t.created_at)}</span></span></p>
                  {d?.summary != null && <p className="mt-0.5 text-muted"><span className="font-semibold text-sea">{CATEGORY[String(d.category)] ?? String(d.category)}</span> · {String(d.language).toUpperCase()} · {String(d.summary)}</p>}
                  {d?.email != null && <p className="mt-0.5 text-muted"><span className="font-semibold text-sea">{String(d.name)}</span> · {String(d.email)}{d.phone ? ` · ${String(d.phone)}` : ""} · {String(d.message)}</p>}
                </div>
                <button onClick={() => close(t.id)} className={ghost}>Mark done</button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------- Coverage

function Coverage() {
  const db = useDb();
  const cards = useRows(() => db.from("coverages").select("id, payer_name, member_id, status, created_at, patients(given_name, family_name, mrn)")
    .order("created_at", { ascending: false }).limit(50) as never, [db]);
  async function decide(id: unknown, status: "verified" | "rejected") {
    await db.from("coverages").update({ status }).eq("id", String(id));
    cards.reload();
  }
  return (
    <div className={`${panel} overflow-x-auto`}>
      {cards.rows === null || cards.error || !cards.rows.length ? <State rows={cards.rows} error={cards.error} empty="No insurance cards waiting." /> : (
        <table className="w-full min-w-[760px] text-left">
          <thead className="border-b border-[#e6ebea] bg-[#f8faf9]"><tr>{["Patient", "Record", "Plan", "Member ID", "Added", "Status", ""].map((h, i) => <th key={i} className={th}>{h}</th>)}</tr></thead>
          <tbody className="divide-y divide-[#eef1f0]">
            {cards.rows.map((c) => (
              <tr key={String(c.id)}>
                <td className={`${td} font-semibold`}>{person(c.patients)}</td>
                <td className={`${td} font-mono text-[12px] text-muted`}>{String((c.patients as Row | null)?.mrn ?? "")}</td>
                <td className={td}>{String(c.payer_name)}</td>
                <td className={`${td} font-mono text-[12px]`}>•••• {String(c.member_id ?? "").slice(-4)}</td>
                <td className={`${td} tabular-nums text-muted`}>{when(c.created_at)}</td>
                <td className={td}><Tag tone={c.status === "verified" ? "teal" : c.status === "rejected" ? "red" : "amber"}>{c.status === "pending_review" ? "To review" : c.status === "verified" ? "Verified" : "Rejected"}</Tag></td>
                <td className={`${td} text-right`}>{c.status === "pending_review" && (
                  <div className="flex justify-end gap-2"><button onClick={() => decide(c.id, "rejected")} className={ghost}>Reject</button><button onClick={() => decide(c.id, "verified")} className={button}>Verify</button></div>
                )}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------- Roster

function Roster({ clinic }: { clinic: string }) {
  const db = useDb();
  const monday = useMemo(() => { const m = dayStart(new Date()); m.setDate(m.getDate() - ((m.getDay() + 6) % 7)); return m; }, []);
  const sunday = new Date(monday); sunday.setDate(sunday.getDate() + 7);
  const shifts = useRows(() => db.from("staff_roster").select("id, starts_at, ends_at, on_call, practitioners(display_name), locations(name)")
    .gte("starts_at", monday.toISOString()).lt("starts_at", sunday.toISOString()).order("starts_at") as never, [db]);
  const rows = (shifts.rows ?? []).filter((r) => inClinic(clinic, r));
  const days = Array.from({ length: 6 }, (_, i) => { const d = new Date(monday); d.setDate(d.getDate() + i); return d; });
  const people = [...new Set(rows.map((r) => clean((r.practitioners as Row | null)?.display_name)))];
  const dayKey = (iso: unknown) => new Date(String(iso)).toLocaleDateString("en-CA", { timeZone: TZ });
  return (
    <div className={`${panel} overflow-x-auto`}>
      {shifts.rows === null || shifts.error || !rows.length ? <State rows={shifts.rows === null ? null : rows} error={shifts.error} empty="No shifts on the roster this week." /> : (
        <table className="w-full min-w-[900px] text-left">
          <thead className="border-b border-[#e6ebea] bg-[#f8faf9]">
            <tr><th className={th}>Clinician</th>{days.map((d) => <th key={d.toISOString()} className={th}>{d.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" })}</th>)}</tr>
          </thead>
          <tbody className="divide-y divide-[#eef1f0]">
            {people.map((name) => (
              <tr key={name}>
                <td className={td}><div className="flex items-center gap-2.5"><Avatar name={name} /><span className="font-semibold">{name}</span></div></td>
                {days.map((d) => {
                  const s = rows.find((r) => clean((r.practitioners as Row | null)?.display_name) === name && dayKey(r.starts_at) === d.toLocaleDateString("en-CA"));
                  return (
                    <td key={d.toISOString()} className="px-2 py-1.5">
                      {s ? (
                        <div className={`border-l-[3px] px-2 py-1 ${s.on_call ? "border-l-apricot bg-[#fdf6ee]" : "border-l-teal bg-[#f1f7f5]"}`}>
                          <p className="font-semibold tabular-nums">{time(s.starts_at)}–{time(s.ends_at)}</p>
                          <p className="text-[11px] text-muted">{String((s.locations as Row | null)?.name ?? "")}{s.on_call ? " · on call" : ""}</p>
                        </div>
                      ) : <span className="px-2 text-[12px] text-muted">Off</span>}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------- Payments

function Payments() {
  const db = useDb();
  const pay = useRows(() => db.from("payments").select("id, amount_cents, status, paid_at, created_at, patients(given_name, family_name)")
    .order("created_at", { ascending: false }).limit(100) as never, [db]);
  const rows = pay.rows ?? [];
  const sum = (status: string) => rows.filter((p) => p.status === status).reduce((s, p) => s + Number(p.amount_cents), 0);
  return (
    <div className="space-y-4">
      <Figures items={[
        ["Collected", money(sum("paid")), `${rows.filter((p) => p.status === "paid").length} payments`],
        ["Waiting", money(sum("pending")), "links sent, not yet paid"],
        ["Refunded", money(sum("refunded"))],
      ]} />
      <div className={`${panel} overflow-x-auto`}>
        {pay.rows === null || pay.error || !rows.length ? <State rows={pay.rows} error={pay.error} empty="No payments yet." /> : (
          <table className="w-full min-w-[620px] text-left">
            <thead className="border-b border-[#e6ebea] bg-[#f8faf9]"><tr>{["When", "Patient", "Amount", "Status"].map((h) => <th key={h} className={th}>{h}</th>)}</tr></thead>
            <tbody className="divide-y divide-[#eef1f0]">
              {rows.map((p) => (
                <tr key={String(p.id)}>
                  <td className={`${td} tabular-nums text-muted`}>{when(p.paid_at ?? p.created_at)}</td>
                  <td className={`${td} font-semibold`}>{p.patients ? person(p.patients) : "Patient"}</td>
                  <td className={`${td} text-right font-semibold tabular-nums sm:text-left`}>{money(Number(p.amount_cents))}</td>
                  <td className={td}><Tag tone={p.status === "paid" ? "teal" : p.status === "refunded" ? "grey" : "amber"}>{p.status === "paid" ? "Paid" : p.status === "refunded" ? "Refunded" : "Waiting"}</Tag></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------- Nora activity

function NoraActivity() {
  const db = useDb();
  const ev = useRows(() => db.from("ai_events").select("id, channel, language, outcome, tools, model, prompt_version, latency_ms, created_at")
    .order("created_at", { ascending: false }).limit(100) as never, [db]);
  if (ev.rows === null || ev.error || !ev.rows.length) return <div className={panel}><State rows={ev.rows} error={ev.error} empty="No conversations with Nora yet." /></div>;
  const rows = ev.rows;
  const count = (o: string) => rows.filter((e) => e.outcome === o).length;
  const lat = rows.map((e) => Number(e.latency_ms)).sort((a, b) => a - b);
  const tools = new Map<string, number>();
  rows.forEach((e) => (e.tools as string[]).forEach((t) => tools.set(t, (tools.get(t) ?? 0) + 1)));
  const top = [...tools.entries()].sort((a, b) => b[1] - a[1]).slice(0, 7);
  return (
    <div className="space-y-4">
      <Figures items={[
        ["Turns", rows.length, "latest 100"],
        ["Passed to the team", `${Math.round((count("handover") / rows.length) * 100)}%`],
        ["Waiting for a button", count("confirm")],
        ["Median reply", `${(lat[Math.floor(lat.length / 2)] / 1000).toFixed(1)} s`],
        ["Slowest reply", `${(lat[lat.length - 1] / 1000).toFixed(1)} s`],
      ]} />
      <div className="grid gap-4 lg:grid-cols-[1fr_1.7fr]">
        <Section title="Tools Nora used">
          <table className="w-full text-left">
            <tbody>
              {top.map(([t, n]) => (
                <tr key={t}>
                  <td className="py-1.5 pr-3 font-mono text-[12px]">{t}</td>
                  <td className="w-1/2 py-1.5"><div className="h-2 bg-[#edf2f1]"><div className="h-2 bg-teal" style={{ width: `${(n / top[0][1]) * 100}%` }} /></div></td>
                  <td className="w-10 py-1.5 text-right tabular-nums">{n}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Section>
        <Section title="Every turn, newest first" action={<span className="text-[11px] text-muted">What Nora did, never what anyone said</span>} flush>
          <div className="max-h-[440px] overflow-y-auto">
            <table className="w-full text-left">
              <thead className="sticky top-0 border-b border-[#e6ebea] bg-[#f8faf9]"><tr>{["When", "Outcome", "Channel", "Tools", "Reply", "Prompt"].map((h) => <th key={h} className={th}>{h}</th>)}</tr></thead>
              <tbody className="divide-y divide-[#eef1f0]">
                {rows.map((e) => (
                  <tr key={String(e.id)}>
                    <td className={`${td} tabular-nums text-muted`}>{when(e.created_at)}</td>
                    <td className={td}><Tag tone={e.outcome === "handover" ? "amber" : e.outcome === "emergency" ? "red" : e.outcome === "confirm" ? "teal" : "grey"}>{String(e.outcome)}</Tag></td>
                    <td className={td}>{String(e.channel)} · {String(e.language).toUpperCase()}</td>
                    <td className={`${td} font-mono text-[12px] text-muted`}>{(e.tools as string[]).join(", ") || "none"}</td>
                    <td className={`${td} tabular-nums`}>{(Number(e.latency_ms) / 1000).toFixed(1)} s</td>
                    <td className={`${td} font-mono text-[12px] text-muted`}>{String(e.prompt_version).slice(0, 7)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Section>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------- Settings

function Settings({ me, onChange }: { me: Me | null; onChange: () => void }) {
  const db = useDb();
  const org = useRows(() => db.from("org_settings").select("settings") as never, [db]);
  const clinics = useRows(() => db.from("effective_location_settings").select("location_id, settings") as never, [db]);
  const names = useRows(() => db.from("locations").select("id, name") as never, [db]);
  const nameOf = (id: unknown) => String((names.rows ?? []).find((l) => l.id === id)?.name ?? "Clinic");
  const admin = me?.role === "org_admin";
  const settings = (org.rows?.[0]?.settings ?? {}) as Row;
  const on = settings.assistant_enabled !== false;
  async function toggle() {
    await db.from("org_settings").update({ settings: { ...settings, assistant_enabled: !on } }).eq("id", 1);
    org.reload(); onChange();
  }
  return (
    <div className="space-y-4">
      <Section title="Nora, the AI receptionist">
        <div className="flex flex-wrap items-center gap-4">
          <span className={`size-2.5 rounded-full ${on ? "bg-shine" : "bg-danger"}`} />
          <div className="min-w-0 flex-1">
            <p className="font-semibold">{on ? "On: answering patients in the app and on calls" : "Off: patients see the clinic's number instead"}</p>
            <p className="text-muted">Turning her off reaches every patient within 30 seconds, in their language, and the model is not used. Audited.</p>
          </div>
          {admin ? <button onClick={toggle} className={on ? "rounded-md border border-danger/40 px-3.5 py-1.5 text-[13px] font-semibold text-danger hover:bg-[#fdf0ef]" : button}>{on ? "Turn Nora off" : "Turn Nora on"}</button>
            : <p className="text-muted">Only a practice manager can change this.</p>}
        </div>
      </Section>
      <Section title="Clinic settings" flush>
        {clinics.rows && !clinics.error && (
          <table className="w-full text-left">
            <thead className="border-b border-[#e6ebea] bg-[#f8faf9]"><tr>{["Clinic", "Notice to cancel", "Missed-visit fee", "Language"].map((h) => <th key={h} className={th}>{h}</th>)}</tr></thead>
            <tbody className="divide-y divide-[#eef1f0]">
              {clinics.rows.map((c) => {
                const s = (c.settings ?? {}) as Row;
                return (
                  <tr key={String(c.location_id)}>
                    <td className={`${td} font-semibold`}>{nameOf(c.location_id)}</td>
                    <td className={`${td} tabular-nums`}>{String(s.cancellation_hours ?? "24")} hours</td>
                    <td className={`${td} tabular-nums`}>{money(Number(s.missed_appointment_fee_cents ?? 0))}</td>
                    <td className={td}>{String(s.language ?? "en").toUpperCase()}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------- Care (W24 to W28)

const PROGRAMME: Record<string, string> = { post_procedure: "Recovery", aligners: "Aligners", recall: "Recall" };
const REASON: Record<string, string> = {
  serious_side_effect: "Serious side effect", worsening_trend: "Worsening trend", missed_wear: "Aligner wear short", missed_checkins: "Missed check-ins",
};

function Care({ clinic }: { clinic: string }) {
  const db = useDb();
  const flags = useRows(() => db.from("care_flags").select("id, reason, data, created_at, patients(given_name, family_name, mrn)")
    .is("resolved_at", null).order("created_at", { ascending: false }) as never, [db]);
  const people = useRows(() => db.from("care_enrolments")
    .select("id, programme, status, starts_on, ends_on, locations(name), patients(given_name, family_name, mrn), care_checkins(due_on, pain, feeling, level, answered_at), care_summaries(week_start, summary)")
    .in("status", ["invited", "active"]).order("starts_on", { ascending: false }) as never, [db]);
  const [outcome, setOutcome] = useState<Record<string, string>>({});
  async function resolve(id: unknown) {
    const text = (outcome[String(id)] ?? "").trim();
    if (text.length < 3) return;
    const { error } = await db.rpc("resolve_care_flag", { flag: String(id), outcome: text });
    if (!error) flags.reload();
  }
  const rows = (people.rows ?? []).filter((r) => inClinic(clinic, r));
  const todayIso = new Date().toLocaleDateString("en-CA", { timeZone: TZ });
  return (
    <div className="space-y-4">
      <Section title="Check-up flags" action={<span className="text-[11px] text-muted">Open until a clinician records the outcome</span>} flush>
        {flags.rows === null || flags.error || !flags.rows.length ? <State rows={flags.rows} error={flags.error} empty="No open check-up flags." /> : (
          <ul className="divide-y divide-[#eef1f0]">
            {flags.rows.map((f) => (
              <li key={String(f.id)} className="grid gap-3 px-4 py-3 md:grid-cols-[1fr_1.2fr]">
                <div>
                  <p><Tag tone={f.reason === "serious_side_effect" ? "red" : "amber"}>{REASON[String(f.reason)] ?? String(f.reason)}</Tag> <b className="ml-1">{person(f.patients)}</b> <span className="font-mono text-[11px] text-muted">{String((f.patients as Row | null)?.mrn ?? "")}</span></p>
                  <p className="mt-1 font-mono text-[11px] text-muted">{JSON.stringify(f.data).slice(0, 140)}</p>
                  <p className="text-[11px] text-muted">{when(f.created_at)} · a booking offer was sent to the patient</p>
                </div>
                <div className="flex items-start gap-2">
                  <input value={outcome[String(f.id)] ?? ""} onChange={(e) => setOutcome((o) => ({ ...o, [String(f.id)]: e.target.value }))}
                    placeholder="Outcome, for example: called, booked for Friday" aria-label="Outcome"
                    className="min-w-0 flex-1 rounded-md border border-[#cfd8d6] px-2.5 py-1.5 outline-none focus:border-teal" />
                  <button onClick={() => resolve(f.id)} className={button}>Record</button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </Section>
      <Section title="Patients in a programme" flush>
        {people.rows === null || people.error || !rows.length ? <State rows={people.rows === null ? null : rows} error={people.error} empty="Nobody is in a care programme." /> : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[900px] text-left">
              <thead className="border-b border-[#e6ebea] bg-[#f8faf9]"><tr>{["Patient", "Programme", "Day", "Today", "Last pain", "This week"].map((h) => <th key={h} className={th}>{h}</th>)}</tr></thead>
              <tbody className="divide-y divide-[#eef1f0]">
                {rows.map((r) => {
                  const checkins = ((r.care_checkins as Row[] | null) ?? []).sort((a, b) => String(b.due_on).localeCompare(String(a.due_on)));
                  const today = checkins.find((c) => c.due_on === todayIso);
                  const lastPain = checkins.find((c) => c.pain != null);
                  const summary = ((r.care_summaries as Row[] | null) ?? []).sort((a, b) => String(b.week_start).localeCompare(String(a.week_start)))[0];
                  const day = Math.floor((Date.parse(todayIso) - Date.parse(String(r.starts_on))) / 86400000) + 1;
                  const total = Math.floor((Date.parse(String(r.ends_on)) - Date.parse(String(r.starts_on))) / 86400000) + 1;
                  return (
                    <tr key={String(r.id)}>
                      <td className={td}><p className="font-semibold">{person(r.patients)}</p><p className="font-mono text-[11px] text-muted">{String((r.patients as Row | null)?.mrn ?? "")} · {String((r.locations as Row | null)?.name ?? "")}</p></td>
                      <td className={td}>{PROGRAMME[String(r.programme)] ?? String(r.programme)}{r.status === "invited" && <span className="ml-1.5"><Tag tone="grey">invited</Tag></span>}</td>
                      <td className={`${td} tabular-nums`}>{r.programme === "recall" ? "–" : `${Math.max(day, 0)} of ${total}`}</td>
                      <td className={td}>{r.programme !== "post_procedure" ? <span className="text-muted">–</span> : !today ? <span className="text-muted">Opens 10:00</span>
                        : !today.answered_at ? <Tag tone="amber">Not answered</Tag>
                        : <Tag tone={today.level === "emergency" ? "red" : today.level === "task" ? "amber" : "teal"}>{String(today.level)}</Tag>}</td>
                      <td className={`${td} tabular-nums`}>{lastPain ? `${String(lastPain.pain)} / 10` : <span className="text-muted">–</span>}</td>
                      <td className={`${td} max-w-xs text-[12px] text-muted`}>{summary ? String(summary.summary) : "No summary yet"}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Section>
    </div>
  );
}
