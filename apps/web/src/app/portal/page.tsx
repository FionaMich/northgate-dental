"use client";
// The staff portal. Everything runs in the browser with the staff member's own session: row level security decides
// what they see (their clinics only) and the staff gate refuses every row until they have passed two-factor sign-in.
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { money } from "@/lib/data";

type Stage = "loading" | "signin" | "mfa" | "enrol" | "ready";
type Row = Record<string, unknown>;

const card = "rounded-3xl bg-white p-6 ring-1 ring-line";
const input = "mt-1 w-full rounded-xl border border-line px-4 py-3 outline-none focus:border-teal focus:ring-4 focus:ring-enamel";
const button = "rounded-full bg-teal px-5 py-2.5 font-bold text-white transition hover:bg-teal-dark disabled:opacity-60";
const time = (iso: unknown) => new Date(String(iso)).toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: "America/New_York" });
const when = (iso: unknown) => new Date(String(iso)).toLocaleString("en-US", { dateStyle: "medium", timeStyle: "short", timeZone: "America/New_York" });

export default function Portal() {
  const [stage, setStage] = useState<Stage>("loading");
  const [message, setMessage] = useState("");
  const [factorId, setFactorId] = useState("");
  const [qr, setQr] = useState("");

  const decide = useCallback(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return setStage("signin");
    const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    if (aal?.currentLevel === "aal2") return setStage("ready");
    const { data: factors } = await supabase.auth.mfa.listFactors();
    const totp = factors?.totp.find((f) => f.status === "verified");
    if (totp) { setFactorId(totp.id); return setStage("mfa"); }
    const { data, error } = await supabase.auth.mfa.enroll({ factorType: "totp", friendlyName: `Portal ${Date.now()}` });
    if (error || !data) { setMessage("Two-factor setup is not available for this account."); return setStage("signin"); }
    setFactorId(data.id); setQr(data.totp.qr_code); setStage("enrol");
  }, []);

  useEffect(() => { void decide(); }, [decide]);

  async function signIn(form: FormData) {
    setMessage("");
    const { error } = await supabase.auth.signInWithPassword({ email: String(form.get("email")), password: String(form.get("password")) });
    if (error) return setMessage("That email and password don't match a staff account.");
    await decide();
  }

  async function verify(form: FormData) {
    setMessage("");
    const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId, code: String(form.get("code")).replace(/\s/g, "") });
    if (error) return setMessage("That code didn't work. Codes change every 30 seconds; try the current one.");
    await decide();
  }

  if (stage === "loading") return <Shell><p className="text-muted">Loading…</p></Shell>;
  if (stage === "signin") return (
    <Shell>
      <form action={signIn} className={`${card} mx-auto max-w-md space-y-4`}>
        <h1 className="text-2xl font-extrabold">Staff sign-in</h1>
        <p className="text-sm text-muted">For the Northgate team. Patients use the app.</p>
        <label className="block text-sm font-semibold">Work email<input name="email" type="email" required autoComplete="username" className={input} /></label>
        <label className="block text-sm font-semibold">Password<input name="password" type="password" required autoComplete="current-password" className={input} /></label>
        {message && <p role="alert" className="text-sm font-semibold text-danger">{message}</p>}
        <button className={button}>Continue</button>
      </form>
    </Shell>
  );
  if (stage === "mfa" || stage === "enrol") return (
    <Shell>
      <form action={verify} className={`${card} mx-auto max-w-md space-y-4`}>
        <h1 className="text-2xl font-extrabold">{stage === "enrol" ? "Set up two-factor sign-in" : "Enter your code"}</h1>
        {stage === "enrol" ? (
          <>
            <p className="text-sm text-muted">Staff accounts need a second step. Scan this with an authenticator app, then enter the 6-digit code it shows.</p>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={qr} alt="QR code for your authenticator app" className="mx-auto size-48" />
          </>
        ) : <p className="text-sm text-muted">Open your authenticator app and enter the 6-digit code for Northgate.</p>}
        <label className="block text-sm font-semibold">Code<input name="code" inputMode="numeric" pattern="[0-9 ]{6,7}" required autoComplete="one-time-code" className={input} /></label>
        {message && <p role="alert" className="text-sm font-semibold text-danger">{message}</p>}
        <button className={button}>Verify</button>
      </form>
    </Shell>
  );
  return <Dashboard onSignOut={async () => { await supabase.auth.signOut(); setStage("signin"); }} />;
}

function Shell({ children }: { children: React.ReactNode }) {
  return <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6">{children}</div>;
}

type Me = { id: string; role: string; display_name: string };
const NAV = [
  ["Schedule", "Who is in the chair today, by dentist"],
  ["My patients", "The dentist desk: your own visits"],
  ["Inbox", "Requests from Nora and the website"],
  ["Coverage", "Insurance cards to check"],
  ["Roster", "Shifts this week"],
  ["Payments", "What came in"],
  ["Nora activity", "What the AI receptionist did"],
  ["Settings", "Clinic settings and the Nora switch"],
] as const;
type Page = (typeof NAV)[number][0];
const ROLE: Record<string, string> = { receptionist: "Front desk", clinician: "Clinician", location_manager: "Clinic manager", org_admin: "Organisation admin" };

function Dashboard({ onSignOut }: { onSignOut: () => void }) {
  const [page, setPage] = useState<Page>("Schedule");
  const [me, setMe] = useState<Me | null>(null);
  useEffect(() => {
    void supabase.auth.getUser().then(async ({ data: { user } }) => {
      const { data } = await supabase.from("profiles").select("id, role, display_name").eq("id", user?.id ?? "").maybeSingle();
      setMe((data as Me | null) ?? null);
    });
  }, []);
  return (
    <div className="mx-auto grid max-w-7xl gap-6 px-4 py-8 sm:px-6 lg:grid-cols-[250px_1fr]">
      <aside className="lg:sticky lg:top-20 lg:self-start">
        <div className="rounded-3xl bg-sea p-5 text-white">
          <p className="text-xs font-semibold tracking-wide text-shine">Staff portal</p>
          <p className="mt-1 text-lg font-extrabold">{me?.display_name ?? "Signed in"}</p>
          <p className="text-sm text-white/70">{ROLE[me?.role ?? ""] ?? ""}</p>
        </div>
        <nav aria-label="Portal" className="mt-4 flex gap-2 overflow-x-auto pb-2 lg:flex-col lg:overflow-visible">
          {NAV.map(([name, hint]) => (
            <button key={name} onClick={() => setPage(name)} aria-current={page === name ? "page" : undefined}
              className={`shrink-0 rounded-2xl px-4 py-3 text-left transition ${page === name ? "bg-white shadow-sm ring-1 ring-line" : "hover:bg-white/70"}`}>
              <span className={`block text-sm font-bold ${page === name ? "text-teal" : "text-sea"}`}>{name}</span>
              <span className="hidden text-xs text-muted lg:block">{hint}</span>
            </button>
          ))}
        </nav>
        <button onClick={onSignOut} className="mt-2 px-4 text-sm font-semibold text-muted hover:text-teal">Sign out</button>
      </aside>
      <section aria-live="polite">
        <h1 className="mb-6 font-display text-3xl font-black tracking-tight">{page}</h1>
        {page === "Schedule" && <Schedule />}
        {page === "My patients" && <Today mine />}
        {page === "Inbox" && <Inbox />}
        {page === "Coverage" && <Coverage />}
        {page === "Roster" && <Roster />}
        {page === "Payments" && <Payments />}
        {page === "Nora activity" && <NoraActivity />}
        {page === "Settings" && <Settings me={me} />}
      </section>
    </div>
  );
}

function useRows(load: () => PromiseLike<{ data: Row[] | null; error: { message: string } | null }>, deps: unknown[] = []) {
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState("");
  const reload = useCallback(() => {
    void load().then(({ data, error }) => { setError(error ? "This list is not available for your account." : ""); setRows(data ?? []); });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  useEffect(reload, [reload]);
  return { rows, error, reload };
}

function Empty({ rows, error, text }: { rows: Row[] | null; error: string; text: string }) {
  if (rows === null) return <p className="text-muted">Loading…</p>;
  if (error) return <p className="text-muted">{error}</p>;
  if (!rows.length) return <p className={`${card} text-muted`}>{text}</p>;
  return null;
}

const KIND: Record<string, string> = {
  assistant_handover: "Passed on by Nora", website_lead: "Website question", schedule_conflict: "Schedule conflict",
  checkin_follow_up: "Check-in follow-up", billing_follow_up: "Billing follow-up", shop_fulfilment: "Shop order",
};

function Inbox() {
  const tasks = useRows(() => supabase.from("staff_tasks").select("id, kind, priority, reference_id, created_at, locations(name)")
    .is("done_at", null).order("created_at", { ascending: false }).limit(50) as never);
  const [details, setDetails] = useState<Record<string, Row>>({});
  useEffect(() => {
    const ids = (k: string) => (tasks.rows ?? []).filter((t) => t.kind === k).map((t) => String(t.reference_id));
    void Promise.all([
      supabase.from("assistant_handovers").select("id, category, language, summary").in("id", ids("assistant_handover")),
      supabase.from("leads").select("id, name, email, phone, message").in("id", ids("website_lead")),
    ]).then(([h, l]) => setDetails(Object.fromEntries([...(h.data ?? []), ...(l.data ?? [])].map((r) => [String(r.id), r as Row]))));
  }, [tasks.rows]);

  async function close(id: unknown) {
    const { data: { user } } = await supabase.auth.getUser();
    await supabase.from("staff_tasks").update({ done_at: new Date().toISOString(), done_by: user?.id }).eq("id", String(id));
    tasks.reload();
  }

  if (tasks.rows === null || tasks.error || !tasks.rows.length)
    return <Empty rows={tasks.rows} error={tasks.error} text="Nothing waiting. New requests from Nora and the website appear here." />;
  return (
    <ul className="space-y-3">
      {tasks.rows.map((t) => {
        const d = details[String(t.reference_id)];
        return (
          <li key={String(t.id)} className={`${card} flex flex-wrap items-start gap-4`}>
            <span className={`rounded-full px-3 py-1 text-xs font-bold ${t.priority === "urgent" ? "bg-danger text-white" : t.priority === "high" ? "bg-apricot text-sea" : "bg-enamel text-teal"}`}>{String(t.priority)}</span>
            <div className="min-w-0 flex-1">
              <p className="font-bold">{KIND[String(t.kind)] ?? String(t.kind)} · {String((t.locations as Row | null)?.name ?? "")}</p>
              {d?.summary != null && <p className="mt-1 text-sm text-muted">{String(d.category)} · {String(d.language).toUpperCase()} · {String(d.summary)}</p>}
              {d?.email != null && <p className="mt-1 text-sm text-muted">{String(d.name)} · {String(d.email)}{d.phone ? ` · ${String(d.phone)}` : ""}<br />{String(d.message)}</p>}
              <p className="mt-1 text-xs text-muted">{when(t.created_at)}</p>
            </div>
            <button onClick={() => close(t.id)} className="text-sm font-bold text-teal hover:underline">Mark done</button>
          </li>
        );
      })}
    </ul>
  );
}

function Today({ mine }: { mine: boolean }) {
  const start = new Date(); start.setHours(0, 0, 0, 0);
  const end = new Date(start); end.setDate(end.getDate() + 1);
  const visits = useRows(async () => {
    // the dentist desk joins only the signed-in clinician's own visits (inner join on their practitioner record)
    let q = supabase.from("appointments")
      .select(`id, starts_at, ends_at, status, patients(given_name, family_name), services(name), locations(name), ${mine ? "practitioners!inner" : "practitioners"}(display_name, profile_id)`)
      .gte("starts_at", start.toISOString()).lt("starts_at", end.toISOString()).neq("status", "cancelled").order("starts_at");
    if (mine) {
      const { data: { user } } = await supabase.auth.getUser();
      q = q.eq("practitioners.profile_id", user?.id ?? "");
    }
    return q as never;
  }, [mine]);
  const empty = <Empty rows={visits.rows} error={visits.error} text={mine ? "No patients booked with you today." : "No visits booked today at your clinics."} />;
  if (visits.rows === null || visits.error || !visits.rows.length) return empty;
  return (
    <div className="overflow-x-auto rounded-3xl bg-white ring-1 ring-line">
      <table className="w-full text-left text-sm">
        <thead className="bg-mist text-muted"><tr>{["Time", "Patient", "Visit", "With", "Clinic", "Status"].map((h) => <th key={h} className="px-5 py-3 font-semibold">{h}</th>)}</tr></thead>
        <tbody>
          {visits.rows.map((v) => {
            const p = v.patients as Row | null;
            return (
              <tr key={String(v.id)} className="border-t border-line">
                <td className="px-5 py-3 font-bold">{time(v.starts_at)}–{time(v.ends_at)}</td>
                <td className="px-5 py-3">{p ? `${String(p.given_name)} ${String(p.family_name)}` : "Not linked"}</td>
                <td className="px-5 py-3">{String((v.services as Row | null)?.name ?? "")}</td>
                <td className="px-5 py-3">{String((v.practitioners as Row | null)?.display_name ?? "")}</td>
                <td className="px-5 py-3">{String((v.locations as Row | null)?.name ?? "")}</td>
                <td className="px-5 py-3"><span className="rounded-full bg-enamel px-3 py-1 text-xs font-bold text-teal">{String(v.status)}</span></td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function Payments() {
  const pay = useRows(() => supabase.from("payments").select("id, amount_cents, status, paid_at, created_at").order("created_at", { ascending: false }).limit(50) as never);
  const empty = <Empty rows={pay.rows} error={pay.error} text="No payments yet." />;
  if (pay.rows === null || pay.error || !pay.rows.length) return empty;
  const paid = pay.rows.filter((p) => p.status === "paid").reduce((s, p) => s + Number(p.amount_cents), 0);
  return (
    <>
      <p className={`${card} mb-4`}><span className="text-sm text-muted">Paid, last 50 payments</span><br /><span className="text-3xl font-extrabold">{money(paid)}</span></p>
      <ul className="divide-y divide-line rounded-3xl bg-white ring-1 ring-line">
        {pay.rows.map((p) => (
          <li key={String(p.id)} className="flex items-center gap-4 px-5 py-3 text-sm">
            <span className="font-bold">{money(Number(p.amount_cents))}</span>
            <span className="rounded-full bg-enamel px-3 py-1 text-xs font-bold text-teal">{String(p.status)}</span>
            <span className="ml-auto text-muted">{when(p.paid_at ?? p.created_at)}</span>
          </li>
        ))}
      </ul>
    </>
  );
}

function NoraActivity() {
  const ev = useRows(() => supabase.from("ai_events").select("id, channel, language, outcome, tools, model, prompt_version, latency_ms, created_at")
    .order("created_at", { ascending: false }).limit(100) as never);
  const empty = <Empty rows={ev.rows} error={ev.error} text="No conversations with Nora yet." />;
  if (ev.rows === null || ev.error || !ev.rows.length) return empty;
  const count = (o: string) => ev.rows!.filter((e) => e.outcome === o).length;
  const p50 = [...ev.rows].map((e) => Number(e.latency_ms)).sort((a, b) => a - b)[Math.floor(ev.rows.length / 2)];
  return (
    <>
      <div className="mb-4 grid gap-3 sm:grid-cols-4">
        {[["Turns", ev.rows.length], ["Passed to the team", count("handover")], ["Waiting for a button", count("confirm")], ["Median reply", `${(p50 / 1000).toFixed(1)} s`]].map(([k, v]) => (
          <div key={String(k)} className={card}><p className="text-sm text-muted">{k}</p><p className="text-2xl font-extrabold">{v}</p></div>
        ))}
      </div>
      <p className="mb-3 text-sm text-muted">What Nora did, never what anyone said: the outcome, the tools she used, and which model and prompt version answered.</p>
      <ul className="divide-y divide-line rounded-3xl bg-white ring-1 ring-line">
        {ev.rows.map((e) => (
          <li key={String(e.id)} className="flex flex-wrap items-center gap-3 px-5 py-3 text-sm">
            <span className="w-36 text-muted">{when(e.created_at)}</span>
            <span className="rounded-full bg-enamel px-3 py-1 text-xs font-bold text-teal">{String(e.outcome)}</span>
            <span>{String(e.channel)} · {String(e.language).toUpperCase()}</span>
            <span className="text-muted">{(e.tools as string[]).join(", ") || "no tools"}</span>
            <span className="ml-auto text-xs text-muted">{String(e.model)} · prompt {String(e.prompt_version)} · {(Number(e.latency_ms) / 1000).toFixed(1)} s</span>
          </li>
        ))}
      </ul>
    </>
  );
}

const dayStart = (d: Date) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };

function Schedule() {
  const [day, setDay] = useState(() => dayStart(new Date()));
  const next = new Date(day); next.setDate(next.getDate() + 1);
  const visits = useRows(() => supabase.from("appointments")
    .select("id, starts_at, ends_at, status, patients(given_name, family_name), services(name), practitioners(display_name), locations(name)")
    .gte("starts_at", day.toISOString()).lt("starts_at", next.toISOString()).neq("status", "cancelled").order("starts_at") as never, [day.getTime()]);
  const move = (n: number) => setDay((d) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; });
  const columns = new Map<string, Row[]>();
  for (const v of visits.rows ?? []) {
    const who = String((v.practitioners as Row | null)?.display_name ?? "Unassigned");
    columns.set(who, [...(columns.get(who) ?? []), v]);
  }
  return (
    <>
      <div className="mb-5 flex flex-wrap items-center gap-2">
        <button onClick={() => move(-1)} className="rounded-full bg-white px-4 py-2 text-sm font-bold ring-1 ring-line hover:text-teal" aria-label="Previous day">Previous</button>
        <button onClick={() => setDay(dayStart(new Date()))} className="rounded-full bg-white px-4 py-2 text-sm font-bold ring-1 ring-line hover:text-teal">Today</button>
        <button onClick={() => move(1)} className="rounded-full bg-white px-4 py-2 text-sm font-bold ring-1 ring-line hover:text-teal" aria-label="Next day">Next</button>
        <p className="ml-2 font-bold">{day.toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" })}</p>
        <p className="ml-auto text-sm text-muted">{(visits.rows ?? []).length} visits</p>
      </div>
      {visits.rows === null || visits.error || !visits.rows.length
        ? <Empty rows={visits.rows} error={visits.error} text="No visits booked on this day at your clinics." />
        : (
          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            {[...columns.entries()].map(([who, list]) => (
              <div key={who} className="rounded-3xl bg-mist p-4">
                <p className="mb-3 px-1 font-extrabold">{who.replace(/ \(.*\)$/, "")}</p>
                <ul className="space-y-2">
                  {list.map((v) => {
                    const p = v.patients as Row | null;
                    return (
                      <li key={String(v.id)} className="rounded-2xl bg-white p-3 ring-1 ring-line">
                        <p className="text-sm font-extrabold text-teal">{time(v.starts_at)}–{time(v.ends_at)}</p>
                        <p className="font-bold">{p ? `${String(p.given_name)} ${String(p.family_name)}` : "Not linked"}</p>
                        <p className="text-sm text-muted">{String((v.services as Row | null)?.name ?? "")} · {String((v.locations as Row | null)?.name ?? "")}</p>
                      </li>
                    );
                  })}
                </ul>
              </div>
            ))}
          </div>
        )}
    </>
  );
}

function Coverage() {
  const cards = useRows(() => supabase.from("coverages").select("id, payer_name, member_id, status, created_at, patients(given_name, family_name)")
    .order("created_at", { ascending: false }).limit(50) as never);
  async function decide(id: unknown, status: "verified" | "rejected") {
    await supabase.from("coverages").update({ status }).eq("id", String(id));
    cards.reload();
  }
  if (cards.rows === null || cards.error || !cards.rows.length)
    return <Empty rows={cards.rows} error={cards.error} text="No insurance cards waiting." />;
  return (
    <ul className="space-y-3">
      {cards.rows.map((c) => {
        const p = c.patients as Row | null;
        const member = String(c.member_id ?? "");
        return (
          <li key={String(c.id)} className={`${card} flex flex-wrap items-center gap-4`}>
            <div className="min-w-0 flex-1">
              <p className="font-bold">{p ? `${String(p.given_name)} ${String(p.family_name)}` : "Patient"} · {String(c.payer_name)}</p>
              <p className="text-sm text-muted">Member ID ending {member.slice(-4) || "?"} · added {when(c.created_at)}</p>
            </div>
            {c.status === "pending_review" ? (
              <div className="flex gap-2">
                <button onClick={() => decide(c.id, "rejected")} className="rounded-full px-4 py-2 text-sm font-bold text-danger ring-1 ring-line hover:bg-mist">Reject</button>
                <button onClick={() => decide(c.id, "verified")} className={button}>Verify</button>
              </div>
            ) : <span className="rounded-full bg-enamel px-3 py-1 text-xs font-bold text-teal">{String(c.status)}</span>}
          </li>
        );
      })}
    </ul>
  );
}

function Roster() {
  const monday = dayStart(new Date()); monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7));
  const sunday = new Date(monday); sunday.setDate(sunday.getDate() + 7);
  const shifts = useRows(() => supabase.from("staff_roster").select("id, starts_at, ends_at, on_call, practitioners(display_name), locations(name)")
    .gte("starts_at", monday.toISOString()).lt("starts_at", sunday.toISOString()).order("starts_at") as never);
  if (shifts.rows === null || shifts.error || !shifts.rows.length)
    return <Empty rows={shifts.rows} error={shifts.error} text="No shifts on the roster this week." />;
  return (
    <div className="overflow-x-auto rounded-3xl bg-white ring-1 ring-line">
      <table className="w-full text-left text-sm">
        <thead className="bg-mist text-muted"><tr>{["Day", "Hours", "Who", "Clinic", ""].map((h) => <th key={h} className="px-5 py-3 font-semibold">{h}</th>)}</tr></thead>
        <tbody>
          {shifts.rows.map((r) => (
            <tr key={String(r.id)} className="border-t border-line">
              <td className="px-5 py-3 font-bold">{new Date(String(r.starts_at)).toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", timeZone: "America/New_York" })}</td>
              <td className="px-5 py-3">{time(r.starts_at)}–{time(r.ends_at)}</td>
              <td className="px-5 py-3">{String((r.practitioners as Row | null)?.display_name ?? "").replace(/ \(.*\)$/, "")}</td>
              <td className="px-5 py-3">{String((r.locations as Row | null)?.name ?? "")}</td>
              <td className="px-5 py-3">{r.on_call ? <span className="rounded-full bg-apricot px-3 py-1 text-xs font-bold text-sea">on call</span> : null}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Settings({ me }: { me: Me | null }) {
  const org = useRows(() => supabase.from("org_settings").select("settings") as never);
  const clinics = useRows(() => supabase.from("effective_location_settings").select("location_id, settings") as never);
  const names = useRows(() => supabase.from("locations").select("id, name") as never);
  const nameOf = (id: unknown) => String((names.rows ?? []).find((l) => l.id === id)?.name ?? "Clinic");
  const admin = me?.role === "org_admin";
  const settings = (org.rows?.[0]?.settings ?? {}) as Record<string, unknown>;
  const on = settings.assistant_enabled !== false;
  async function toggle() {
    await supabase.from("org_settings").update({ settings: { ...settings, assistant_enabled: !on } }).eq("id", 1);
    org.reload();
  }
  return (
    <div className="space-y-6">
      <div className={`${card} flex flex-wrap items-center gap-4`}>
        <div className="min-w-0 flex-1">
          <p className="text-lg font-extrabold">Nora, the AI receptionist</p>
          <p className="text-sm text-muted">Off means every patient gets a fixed message with the clinic&apos;s number within 30 seconds, and the model is not used. Changes are audited.</p>
        </div>
        <span className={`rounded-full px-3 py-1 text-xs font-bold ${on ? "bg-enamel text-teal" : "bg-danger text-white"}`}>{on ? "On" : "Off"}</span>
        {admin && <button onClick={toggle} className={on ? "rounded-full px-5 py-2.5 font-bold text-danger ring-1 ring-line hover:bg-mist" : button}>{on ? "Turn Nora off" : "Turn Nora on"}</button>}
      </div>
      {!admin && <p className="text-sm text-muted">Only an organisation admin can turn Nora off or on.</p>}
      {clinics.rows && !clinics.error && (
        <div className="grid gap-4 md:grid-cols-3">
          {clinics.rows.map((c) => {
            const s = (c.settings ?? {}) as Record<string, unknown>;
            return (
              <div key={String(c.location_id)} className={card}>
                <p className="font-extrabold">{nameOf(c.location_id)}</p>
                <dl className="mt-3 space-y-1 text-sm">
                  <div className="flex justify-between"><dt className="text-muted">Cancel notice</dt><dd className="font-bold">{String(s.cancellation_hours ?? "24")} hours</dd></div>
                  <div className="flex justify-between"><dt className="text-muted">Missed-visit fee</dt><dd className="font-bold">{money(Number(s.missed_appointment_fee_cents ?? 0))}</dd></div>
                  <div className="flex justify-between"><dt className="text-muted">Language</dt><dd className="font-bold">{String(s.language ?? "en").toUpperCase()}</dd></div>
                </dl>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
