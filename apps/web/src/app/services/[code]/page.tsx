import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import { DETAILS, TEAM, catalogue, money, servicePicture } from "@/lib/data";

export async function generateStaticParams() {
  return (await catalogue()).services.map((s) => ({ code: s.code }));
}

export async function generateMetadata({ params }: { params: Promise<{ code: string }> }): Promise<Metadata> {
  const { code } = await params;
  const s = (await catalogue()).services.find((x) => x.code === code);
  return s ? { title: s.name, description: s.summary } : {};
}

export default async function ServicePage({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const { services, locations } = await catalogue();
  const s = services.find((x) => x.code === code);
  if (!s) notFound();
  const detail = DETAILS[s.code];
  const person = TEAM.find((p) => p.name === detail?.who);
  return (
    <article>
      <section className="relative isolate overflow-hidden bg-sea text-white">
        <Image src={servicePicture(s.code)} alt="" fill priority className="-z-10 object-cover opacity-30" sizes="100vw" />
        <div aria-hidden className="absolute inset-0 -z-10 bg-gradient-to-r from-sea via-sea/90 to-sea/40" />
        <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6 md:py-24">
          <Link href="/services" className="text-sm font-semibold text-shine hover:underline">All services and prices</Link>
          <h1 className="mt-4 max-w-3xl font-display text-4xl font-black tracking-tight sm:text-5xl">{s.name}</h1>
          <p className="mt-5 max-w-2xl text-lg leading-8 text-white/80">{s.summary}</p>
          <p className="mt-6 inline-block rounded-full bg-white/10 px-4 py-2 text-sm font-semibold ring-1 ring-white/20">About {s.duration_minutes} minutes</p>
        </div>
      </section>

      <div className="mx-auto grid max-w-6xl gap-12 px-4 py-16 sm:px-6 lg:grid-cols-[1.3fr_0.7fr]">
        <div>
          <h2 className="text-2xl font-extrabold">What happens at your visit</h2>
          <ol className="mt-6 space-y-4">
            {(detail?.steps ?? []).map((step, i) => (
              <li key={step} className="flex gap-4">
                <span className="grid size-9 shrink-0 place-items-center rounded-full bg-enamel font-extrabold text-teal">{i + 1}</span>
                <p className="pt-1.5 leading-7 text-muted">{step}</p>
              </li>
            ))}
          </ol>
          <h2 className="mt-12 text-2xl font-extrabold">Price at each clinic</h2>
          <dl className="mt-5 grid gap-3 sm:grid-cols-3">
            {locations.map((l) => (
              <div key={l.code} className="rounded-2xl bg-mist px-5 py-4">
                <dt className="text-sm text-muted">{l.name}</dt>
                <dd className={s.prices[l.code] != null ? "text-2xl font-extrabold" : "mt-1 text-muted"}>
                  {s.prices[l.code] != null ? money(s.prices[l.code]) : "Not offered here"}
                </dd>
              </div>
            ))}
          </dl>
          <p className="mt-4 text-sm text-muted">Self-pay prices. With insurance we bill your plan and give you a written estimate before larger treatment.</p>
        </div>

        <aside className="space-y-6">
          {person && (
            <div className="rounded-3xl bg-white p-6 ring-1 ring-line">
              <p className="text-sm font-semibold text-muted">You will usually see</p>
              <div className="mt-4 flex items-center gap-4">
                <Image src={`/images/team/${person.photo}.jpg`} alt={person.name} width={64} height={64} className="size-16 rounded-2xl object-cover" />
                <div>
                  <p className="font-extrabold">{person.name}</p>
                  <p className="text-sm font-semibold text-teal">{person.title}</p>
                </div>
              </div>
              <p className="mt-4 text-sm leading-6 text-muted">{person.bio}</p>
            </div>
          )}
          <div className="rounded-3xl bg-sea p-6 text-white">
            <p className="text-lg font-extrabold">Book in the app</p>
            <p className="mt-2 text-sm text-white/75">Pick a clinic and time, confirm with one tap, and pay securely. Or ask Nora, any hour, in eight languages.</p>
            <Link href="/#app" className="mt-5 inline-block rounded-full bg-shine px-5 py-2.5 text-sm font-bold text-sea hover:bg-white">Get the app</Link>
          </div>
          <div className="rounded-3xl bg-white p-6 text-sm leading-6 text-muted ring-1 ring-line">
            <p className="font-bold text-sea">Good to know</p>
            <p className="mt-2">Please give 24 hours notice to cancel or move a visit. A missed visit costs $50 at Back Bay and Cambridge; Quincy doesn&apos;t charge it.</p>
            <p className="mt-2">Treatment over $500 can be spread over up to 6 monthly payments with no interest.</p>
          </div>
        </aside>
      </div>
    </article>
  );
}
