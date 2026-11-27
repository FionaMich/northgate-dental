// The public catalogue: read from public_catalogue() at build time, with the snapshot in src/data as the fallback,
// so the site still builds when the API is unreachable. No patient data is ever part of it.
import snapshot from "@/data/catalogue.json";

export type Hours = { weekday: number; opens: string; closes: string };
export type Location = { code: string; name: string; address: string; city: string; state: string; postal_code: string; phone: string; hours: Hours[] };
export type Service = { code: string; name: string; summary: string; duration_minutes: number; prices: Record<string, number> };
export type Catalogue = { locations: Location[]; services: Service[] };

export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
export const SUPABASE_KEY = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "";

export async function catalogue(): Promise<Catalogue> {
  if (!SUPABASE_URL || !SUPABASE_KEY) return snapshot as Catalogue;
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/public_catalogue`, {
      method: "POST",
      headers: { apikey: SUPABASE_KEY, "Content-Type": "application/json" },
      body: "{}",
    });
    if (!r.ok) return snapshot as Catalogue;
    return (await r.json()) as Catalogue;
  } catch {
    return snapshot as Catalogue;
  }
}

export const money = (cents: number) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: cents % 100 ? 2 : 0 }).format(cents / 100);

export const phone = (e164: string) => e164.replace(/^\+1(\d{3})(\d{3})(\d{4})$/, "($1) $2-$3");

const DAYS = ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
export function openingLines(hours: Hours[]): string[] {
  // Group consecutive days with the same hours: "Monday to Friday 08:00 to 18:00".
  const lines: string[] = [];
  let i = 0;
  while (i < hours.length) {
    let j = i;
    while (j + 1 < hours.length && hours[j + 1].opens === hours[i].opens && hours[j + 1].closes === hours[i].closes
           && hours[j + 1].weekday === hours[j].weekday + 1) j++;
    const days = i === j ? DAYS[hours[i].weekday] : `${DAYS[hours[i].weekday]} to ${DAYS[hours[j].weekday]}`;
    lines.push(`${days}, ${hours[i].opens} to ${hours[i].closes}`);
    i = j + 1;
  }
  return lines.concat(hours.some((h) => h.weekday === 7) ? [] : ["Sunday, closed"]);
}

// Service pictures by family (bundled, generated for the fictional clinic; see public/images/CREDITS.md).
const PICTURE: Record<string, string> = {
  D0150: "checkups", D1110: "checkups", D1120: "checkups", D9995: "checkups", D9110: "checkups",
  D2391: "fillings", D3330: "fillings", D5110: "fillings",
  D7140: "surgery", D6010: "surgery",
  D8090: "orthodontics", D9972: "cosmetic",
};
// A video consultation is a conversation with a dentist, so it shows one.
export const servicePicture = (code: string) =>
  code === "D9995" ? "/images/team/hannah-brooks.jpg" : `/images/services/${PICTURE[code] ?? "checkups"}.jpg`;

export const TEAM = [
  { name: "Dr Hannah Brooks", title: "General dentist", photo: "hannah-brooks", bio: "Hannah looks after the whole family, from check-ups to fillings and crowns, and believes in fixing small problems early." },
  { name: "Priya Raman, RDH", title: "Dental hygienist", photo: "priya-raman", bio: "Priya gives thorough, gentle cleanings and shows you the small changes at home that keep your gums healthy between visits." },
  { name: "Dr Mei Chen", title: "Orthodontist", photo: "mei-chen", bio: "Mei straightens smiles for teenagers and adults, and plans every aligner case from a 3D scan so you can see the result before you start." },
  { name: "Dr Diego Alvarez", title: "Children's dentist", photo: "diego-alvarez", bio: "Diego makes the dentist a fun place for children, with check-ups, sealants and plenty of time for questions from parents." },
  { name: "Dr Samuel Okafor", title: "Endodontist", photo: "samuel-okafor", bio: "Samuel saves teeth with calm, unhurried root canal treatment, and explains every step so nothing comes as a surprise." },
  { name: "Dr Laura Bennett", title: "Oral surgeon", photo: "laura-bennett", bio: "Laura looks after wisdom teeth, extractions and implants, planning each procedure with a 3D scan for a quicker recovery." },
];

// From knowledge/getting-here.md, the same approved text Nora answers from.
export const ACCESS: Record<string, string> = {
  "back-bay": "Street parking is limited; the public garage on the next block is easiest. A short walk from the subway. Step-free entrance and a lift to the treatment rooms.",
  cambridge: "Two patient parking spaces behind the building and bike racks at the front door. Step-free entrance.",
  quincy: "Free parking in the clinic's own car park, with two accessible spaces by the door. Step-free entrance.",
};

// What a visit is like, for each service page. How the visit runs, never clinical advice: the dentist explains the
// clinical side at the visit. Who you usually see comes from the team above.
export const DETAILS: Record<string, { who: string; steps: string[] }> = {
  D0150: { who: "Dr Hannah Brooks", steps: ["Check in with your ID and insurance card, or in the app before you arrive.", "The dentist looks at your teeth, gums and bite, and takes X-rays only if they are needed.", "You leave with a written plan and prices for anything the dentist suggests.", "Book any follow-up visit in the app or at the desk."] },
  D1110: { who: "Priya Raman, RDH", steps: ["A hygienist removes plaque and tartar, then polishes your teeth.", "You get a few tips on what to focus on at home.", "Most people book their next cleaning in six months; the app reminds you."] },
  D1120: { who: "Dr Diego Alvarez", steps: ["A parent or guardian stays with children under 12.", "A gentle clean and polish, with brushing tips the child can follow.", "A quick check on growing teeth, with time for parents' questions."] },
  D2391: { who: "Dr Hannah Brooks", steps: ["The dentist explains the filling and the price before starting.", "Numbing first, so you feel pressure rather than pain.", "A tooth-coloured filling, usually finished in one visit."] },
  D7140: { who: "Dr Laura Bennett", steps: ["The dentist checks the tooth and explains the plan and price first.", "Numbing so you feel pressure, not pain.", "You get written aftercare from the dentist before you leave."] },
  D3330: { who: "Dr Samuel Okafor", steps: ["An X-ray and a check of the tooth before treatment starts.", "Treatment under numbing, unhurried, with each step explained.", "Often one long visit; sometimes a second to finish."] },
  D6010: { who: "Dr Laura Bennett", steps: ["A 3D scan to plan where the implant goes, at Back Bay.", "Placement under numbing, with written aftercare.", "Healing takes a few months before the crown goes on; we plan each step with you."] },
  D8090: { who: "Dr Mei Chen", steps: ["A 3D scan, so you see the planned result before you start.", "Clear aligners you change every couple of weeks, worn about 22 hours a day.", "Check-ins along the way; the app's aligner timer helps you keep track."] },
  D9972: { who: "Dr Hannah Brooks", steps: ["A quick check that whitening suits your teeth.", "Whitening in the clinic, with protection for your gums.", "Advice on keeping the colour afterwards."] },
  D5110: { who: "Dr Hannah Brooks", steps: ["Impressions and measurements at the first visit.", "A few fittings to get the fit and look right.", "Adjustments after you start wearing it, at no extra charge."] },
  D9110: { who: "The dentist on duty", steps: ["Call your clinic: we keep time free every day for urgent visits.", "The dentist relieves the pain or protects the tooth first.", "You leave with a plan for any treatment that follows."] },
  D9995: { who: "Dr Hannah Brooks", steps: ["Book in the app or with Nora and pay in advance with a secure link.", "Join from Visits in the app; the Join button appears 10 minutes before.", "The dentist advises you, or helps you decide what to book next. We never record the call."] },
};
