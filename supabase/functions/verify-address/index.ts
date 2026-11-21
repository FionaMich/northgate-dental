// Checks a US home address against the US Census Bureau geocoder and returns the standard form of each match.
// Runs in Supabase's US region because the geocoder refuses requests from outside the US.
// Signed-in users only: the function asks Supabase Auth whose token it is (the gateway alone also lets the
// public app key through). The address is never logged or stored here.
// Data flow and vendor: docs/adr/0007-census-geocoder.md.

const CENSUS = "https://geocoding.geo.census.gov/geocoder/locations/address";

type Match = { line1: string; city: string; state: string; zip: string; lat: number; lon: number };

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const clean = (v: unknown, max: number) => (typeof v === "string" ? v.trim().slice(0, max) : "");

// True when the request carries a real user's access token (not just the app's public key).
async function signedIn(req: Request): Promise<boolean> {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return false;
  const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/user`, {
    headers: { Authorization: auth, apikey: Deno.env.get("SUPABASE_ANON_KEY") ?? "" },
  });
  return res.ok && typeof (await res.json())?.id === "string";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "use POST" }, 405);
  if (!(await signedIn(req))) return json({ error: "sign in first" }, 401);
  let input: Record<string, unknown>;
  try {
    input = await req.json();
  } catch {
    return json({ error: "send JSON" }, 400);
  }
  const street = clean(input.street, 120), city = clean(input.city, 80), state = clean(input.state, 2), zip = clean(input.zip, 10);
  if (!street || !/^[A-Za-z]{2}$/.test(state) || !/^\d{5}(-\d{4})?$/.test(zip)) return json({ error: "street, state and ZIP code are required" }, 400);

  const url = new URL(CENSUS);
  for (const [k, v] of Object.entries({ street, city, state, zip, benchmark: "Public_AR_Current", format: "json" })) url.searchParams.set(k, v);
  let body: { result?: { addressMatches?: Array<Record<string, any>> } };
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) return json({ error: "address service unavailable" }, 503);
    body = await res.json();
  } catch {
    return json({ error: "address service unavailable" }, 503);
  }

  // matchedAddress keeps the house number as typed: "4600 SILVER HILL RD, WASHINGTON, DC, 20233".
  const title = (t: string) => t.toLowerCase().replace(/\b[a-z]/g, (ch) => ch.toUpperCase());
  const matches: Match[] = (body.result?.addressMatches ?? []).slice(0, 3).flatMap((m) => {
    const parts = String(m.matchedAddress ?? "").split(", ");
    if (parts.length !== 4) return [];
    const [line1, mcity, mstate, mzip] = parts;
    return [{ line1: title(line1), city: title(mcity), state: mstate, zip: mzip, lat: m.coordinates?.y, lon: m.coordinates?.x }];
  });
  return json({ matches });
});
