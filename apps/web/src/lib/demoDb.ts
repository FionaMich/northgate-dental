// The public demo of the staff portal: a stand-in for the Supabase client that answers the same queries with sample
// data made in the browser. Nothing is read from or written to any database; changes (Mark done, Verify, the Nora
// switch) live in memory until the page is reloaded. Every person and visit here is invented.
import type { SupabaseClient } from "@supabase/supabase-js";

type Row = Record<string, unknown>;

const CLINICS = [
  { id: "loc-bb", name: "Back Bay" }, { id: "loc-cam", name: "Cambridge" }, { id: "loc-q", name: "Quincy" },
];
const DENTISTS = [
  { display_name: "Dr Hannah Brooks", services: ["Comprehensive oral exam", "Composite filling, one surface", "Whitening", "Video consultation"], clinic: 2 },
  { display_name: "Priya Raman, RDH", services: ["Adult cleaning", "Adult cleaning", "Adult cleaning"], clinic: 0 },
  { display_name: "Dr Mei Chen", services: ["Comprehensive orthodontics (clear aligners)", "Aligner check"], clinic: 1 },
  { display_name: "Dr Diego Alvarez", services: ["Child cleaning", "Child cleaning", "Comprehensive oral exam"], clinic: 1 },
  { display_name: "Dr Samuel Okafor", services: ["Root canal, molar", "Comprehensive oral exam"], clinic: 0 },
  { display_name: "Dr Laura Bennett", services: ["Simple extraction", "Implant placement", "Comprehensive oral exam"], clinic: 0 },
];
const NAMES = [
  ["Michelle", "Carter"], ["Daniel", "Okoye"], ["Sofia", "Marquez"], ["Liam", "O'Brien"], ["Aisha", "Rahman"],
  ["Noah", "Kim"], ["Grace", "Whitaker"], ["Mateo", "Rossi"], ["Hannah", "Lindqvist"], ["Ethan", "Nguyen"],
  ["Zara", "Patel"], ["Lucas", "Jansen"], ["Emma", "Kowalski"], ["Owen", "Fitzgerald"], ["Maya", "Haddad"],
  ["Jonas", "Petrauskas"], ["Chloe", "Dubois"], ["Isaac", "Mensah"], ["Ava", "Moretti"], ["Samuel", "Berg"],
  ["Priya", "Shah"], ["Connor", "Walsh"], ["Ines", "Carvalho"], ["Malik", "Johnson"], ["Freya", "Andersson"],
  ["Diego", "Herrera"], ["Lena", "Vogel"], ["Kofi", "Asante"], ["Yuki", "Tanaka"], ["Rosa", "Bianchi"],
  ["Elijah", "Brooks"], ["Mila", "Novak"], ["Arjun", "Mehta"], ["Clara", "Schmidt"], ["Tomás", "Ortega"],
  ["Nadia", "Karim"], ["Felix", "Lindgren"], ["Amara", "Obi"], ["Leo", "Marchetti"], ["Sara", "Vasquez"],
  ["Hugo", "Lefèvre"], ["Ruth", "Coleman"], ["Benjamin", "Adler"], ["Ana", "Silva"], ["Patrick", "Doyle"],
  ["Ingrid", "Holm"], ["Marcus", "Reed"], ["Leila", "Nasser"], ["Viktor", "Kazlauskas"], ["Julia", "Esposito"],
  ["Sean", "Murphy"], ["Elena", "Popescu"], ["Theo", "van Dijk"], ["Nora", "Eriksson"], ["Omar", "Farouk"],
  ["Lucy", "Bennett"], ["Rafael", "Costa"], ["Agnes", "Kowal"], ["David", "Cohen"], ["Mei", "Lin"],
].map(([given_name, family_name], i) => ({ given_name, family_name, mrn: `NG-${(204117 + i * 389).toString().padStart(6, "0")}` }));

// The same day always gets the same schedule, so moving back and forth is stable.
function seeded(seed: number) {   // mulberry32: small, fast, and well spread
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Clinic hours are Boston time, whatever the viewer's clock: midnight in Boston is 05:00 UTC from November to March.
const boston = (d: Date, minutes: number) => new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate(), 5, minutes));

function day(iso: string | undefined) {
  const d = iso ? new Date(iso) : new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}

function appointments(from: Date): Row[] {
  const rnd = seeded(from.getFullYear() * 400 + from.getMonth() * 32 + from.getDate());
  if (from.getDay() === 0) return [];   // closed on Sundays
  const now = Date.now();
  const rows: Row[] = [];
  DENTISTS.forEach((d, di) => {
    let minutes = 8 * 60 + Math.floor(rnd() * 3) * 30;
    while (minutes < 17 * 60) {
      const length = [30, 45, 60, 60, 90][Math.floor(rnd() * 5)];
      if (rnd() > 0.22) {
        const start = boston(from, minutes);
        const end = new Date(start.getTime() + length * 60000);
        const p = NAMES[Math.floor(rnd() * NAMES.length)];
        rows.push({
          id: `a-${di}-${minutes}`, starts_at: start.toISOString(), ends_at: end.toISOString(),
          status: end.getTime() < now ? "completed" : start.getTime() < now ? "checked_in" : "booked",
          patients: p, services: { name: d.services[Math.floor(rnd() * d.services.length)] },
          practitioners: { display_name: d.display_name, profile_id: `p-${di}` },
          locations: { name: CLINICS[d.clinic].name },
        });
      }
      minutes += length + (rnd() > 0.7 ? 30 : 0);
    }
  });
  return rows.sort((a, b) => String(a.starts_at).localeCompare(String(b.starts_at)));
}

const ago = (minutes: number) => new Date(Date.now() - minutes * 60000).toISOString();

function store(): Record<string, Row[]> {
  const handovers = [
    { id: "h1", category: "billing", language: "es", summary: "Asks why the balance after her cleaning is higher than the estimate; insurance paid less than expected." },
    { id: "h2", category: "clinical_question", language: "en", summary: "Asks whether sensitivity after yesterday's filling is normal. Not advised; passed to the dentist." },
    { id: "h3", category: "other", language: "nl", summary: "The patient asked to speak to the team about moving her aligner start date. Reply in the app." },
  ];
  const leads = [
    { id: "l1", name: "Rachel Kim", email: "rachel.kim@example.com", phone: "(617) 555-0188", message: "Do you see children on Saturdays at Quincy? My son is 6." },
    { id: "l2", name: "Tomás Ortega", email: "tomas.o@example.com", phone: null, message: "Is clear aligner treatment possible if I had braces as a teenager?" },
  ];
  return {
    profiles: [{ id: "demo", role: "org_admin", display_name: "Michelle Fiona Opiyo" }],
    patients: NAMES.map((p, i) => {
      const r = seeded(i * 31 + 5);
      const dob = new Date(1948 + Math.floor(r() * 66), Math.floor(r() * 12), 1 + Math.floor(r() * 27));
      const next = r() > 0.35 ? new Date(Date.now() + (1 + Math.floor(r() * 40)) * 86400000) : null;
      if (next) next.setUTCHours(13 + Math.floor(r() * 8), r() > 0.5 ? 30 : 0, 0, 0);
      return { id: `pt-${i}`, ...p, date_of_birth: dob.toISOString().slice(0, 10),
        preferred_language: ["en", "en", "en", "en", "es", "es", "pt", "fr", "nl", "zh", "it", "de", "lt", "sv"][Math.floor(r() * 14)],
        locations: { name: CLINICS[Math.floor(r() * 3)].name }, next_visit: next?.toISOString() ?? null,
        insurance: ["Verified", "Verified", "Verified", "To review", "Self-pay"][Math.floor(r() * 5)],
        balance_cents: r() > 0.72 ? [4500, 12000, 18500, 21000, 32500][Math.floor(r() * 5)] : 0 };
    }),
    staff_tasks: [
      { id: "t1", kind: "assistant_handover", priority: "high", reference_id: "h2", created_at: ago(18), done_at: null, locations: { name: "Quincy" } },
      { id: "t2", kind: "website_lead", priority: "normal", reference_id: "l1", created_at: ago(42), done_at: null, locations: { name: "Quincy" } },
      { id: "t3", kind: "assistant_handover", priority: "normal", reference_id: "h1", created_at: ago(65), done_at: null, locations: { name: "Back Bay" } },
      { id: "t4", kind: "schedule_conflict", priority: "urgent", reference_id: null, created_at: ago(90), done_at: null, locations: { name: "Cambridge" } },
      { id: "t5", kind: "website_lead", priority: "normal", reference_id: "l2", created_at: ago(140), done_at: null, locations: { name: "Cambridge" } },
      { id: "t6", kind: "assistant_handover", priority: "normal", reference_id: "h3", created_at: ago(200), done_at: null, locations: { name: "Cambridge" } },
      { id: "t7", kind: "billing_follow_up", priority: "normal", reference_id: null, created_at: ago(260), done_at: null, locations: { name: "Back Bay" } },
      { id: "t8", kind: "shop_fulfilment", priority: "normal", reference_id: null, created_at: ago(320), done_at: null, locations: { name: "Quincy" } },
    ],
    assistant_handovers: handovers,
    leads,
    coverages: [
      { id: "c1", payer_name: "Harborline Dental PPO", member_id: "HDL-55318204", status: "pending_review", created_at: ago(35), patients: NAMES[2] },
      { id: "c2", payer_name: "Beacon Mutual Dental", member_id: "BMD-77101952", status: "pending_review", created_at: ago(95), patients: NAMES[5] },
      { id: "c3", payer_name: "Commonwealth Smile Plan", member_id: "CSP-30044718", status: "pending_review", created_at: ago(180), patients: NAMES[11] },
      { id: "c4", payer_name: "Pilgrim Health Dental", member_id: "PHD-12099381", status: "verified", created_at: ago(1500), patients: NAMES[7] },
      { id: "c5", payer_name: "Seaport Benefits Dental", member_id: "SBD-88456120", status: "rejected", created_at: ago(2900), patients: NAMES[14] },
    ],
    payments: [13000, 4500, 21000, 15000, 11000, 125000, 12000, 18000, 45000, 9000, 22000, 4500, 20000, 13000, 320000, 12000,
      15000, 11000, 4500, 21000, 13000, 9000, 18000, 12000, 4500, 22000, 13000, 160000, 11000, 15000, 20000, 4500]
      .map((amount_cents, i) => ({ id: `pay-${i}`, amount_cents, patients: NAMES[(i * 7) % NAMES.length], status: i === 3 || i === 17 ? "pending" : i === 9 ? "refunded" : "paid",
        paid_at: i === 3 || i === 17 ? null : ago(12 + i * 61), created_at: ago(12 + i * 61) })),
    ai_events: Array.from({ length: 96 }, (_, i) => {
      const r = seeded(i + 7);
      const kinds = [
        { outcome: "answered", tools: ["clinic_info"] }, { outcome: "answered", tools: ["search_clinic_knowledge"] },
        { outcome: "confirm", tools: ["find_slots", "book_visit"] }, { outcome: "answered", tools: ["pay_link"] },
        { outcome: "answered", tools: ["find_slots"] }, { outcome: "handover", tools: ["handoff_to_staff"] },
        { outcome: "answered", tools: ["my_visits"] }, { outcome: "confirm", tools: ["cancel_visit"] },
      ];
      const k = kinds[Math.floor(r() * kinds.length)];
      return { id: `e-${i}`, channel: r() > 0.85 ? "call" : "chat", language: ["en", "en", "en", "es", "nl", "fr", "de", "it", "sv", "lt"][Math.floor(r() * 10)],
        outcome: k.outcome, tools: k.tools, model: "ollama:gemma4:e4b-it-qat", prompt_version: "4f1c9a7e2b30",
        latency_ms: Math.round(9000 + r() * 26000), created_at: ago(4 + i * 11) };
    }),
    org_settings: [{ id: 1, settings: { language: "en", cancellation_hours: 24, missed_appointment_fee_cents: 5000, assistant_enabled: true } }],
    effective_location_settings: CLINICS.map((c, i) => ({ location_id: c.id,
      settings: { language: "en", cancellation_hours: 24, missed_appointment_fee_cents: i === 2 ? 0 : 5000 } })),
    locations: CLINICS,
  };
}

function roster(): Row[] {
  const monday = day(undefined); monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7));
  const rows: Row[] = [];
  for (let d = 0; d < 6; d++) {
    DENTISTS.forEach((p, i) => {
      if ((d + i) % 4 === 3) return;   // a day off now and then
      const date = new Date(monday); date.setDate(date.getDate() + d);
      const start = boston(date, (d === 5 ? 9 : 8) * 60);
      const end = boston(date, (d === 5 ? 14 : 17) * 60);
      rows.push({ id: `r-${d}-${i}`, starts_at: start.toISOString(), ends_at: end.toISOString(), on_call: (d + i) % 6 === 0,
        practitioners: { display_name: p.display_name }, locations: { name: CLINICS[p.clinic].name } });
    });
  }
  return rows;
}

class Query implements PromiseLike<{ data: unknown; error: null }> {
  private filters: ((r: Row) => boolean)[] = [];
  private single = false;
  private patch: Row | null = null;
  private from?: string;
  constructor(private table: string, private db: Record<string, Row[]>) {}
  select() { return this; }
  order() { return this; }
  limit() { return this; }
  neq(col: string, v: unknown) { this.filters.push((r) => r[col] !== v); return this; }
  is(col: string, v: unknown) { this.filters.push((r) => (r[col] ?? null) === v); return this; }
  in(col: string, vs: unknown[]) { this.filters.push((r) => vs.includes(r[col])); return this; }
  lt() { return this; }
  gte(col: string, v: string) { if (col === "starts_at") this.from = v; return this; }
  eq(col: string, v: unknown) {
    if (col.includes(".")) { const [rel, field] = col.split("."); this.filters.push((r) => (r[rel] as Row | undefined)?.[field] === v); }
    else this.filters.push((r) => r[col] === v);
    return this;
  }
  maybeSingle() { this.single = true; return this; }
  update(values: Row) { this.patch = values; return this; }
  then<A, B>(ok?: ((v: { data: unknown; error: null }) => A | PromiseLike<A>) | null, fail?: ((e: unknown) => B | PromiseLike<B>) | null) {
    const source = this.table === "appointments" ? appointments(day(this.from)) : this.table === "staff_roster" ? roster() : this.db[this.table] ?? [];
    let rows = source.filter((r) => this.filters.every((f) => f(r)));
    if (this.patch) { rows.forEach((r) => Object.assign(r, this.patch)); rows = []; }
    const data = this.single ? rows[0] ?? null : rows;
    return Promise.resolve({ data, error: null }).then(ok, fail);
  }
}

export function demoDb(): SupabaseClient {
  const db = store();
  return {
    from: (table: string) => new Query(table, db),
    auth: { getUser: async () => ({ data: { user: { id: "demo" } }, error: null }) },
  } as unknown as SupabaseClient;
}
