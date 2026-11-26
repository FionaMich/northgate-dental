import Image from "next/image";
import Link from "next/link";
import EnquiryForm from "@/components/EnquiryForm";
import { ACCESS, TEAM, catalogue, money, openingLines, phone, servicePicture } from "@/lib/data";

const FEATURED = ["D0150", "D2391", "D9995", "D8090", "D9972", "D6010"];

export default async function Home() {
  const { locations, services } = await catalogue();
  const featured = FEATURED.map((c) => services.find((s) => s.code === c)).filter(Boolean) as typeof services;
  return (
    <>
      {/* Hero */}
      <section className="relative isolate overflow-hidden bg-sea text-white">
        <Image src="/images/intro_clinic.jpg" alt="" fill priority className="-z-10 object-cover opacity-35" sizes="100vw" />
        <div aria-hidden className="absolute inset-0 -z-10 bg-gradient-to-r from-sea via-sea/85 to-sea/30" />
        <div className="mx-auto grid max-w-6xl gap-10 px-4 py-20 sm:px-6 md:grid-cols-[1.2fr_0.8fr] md:py-28">
          <div>
            <p className="rise text-sm font-semibold text-shine">Back Bay · Cambridge · Quincy</p>
            <h1 className="rise rise-2 mt-4 font-display text-4xl leading-[1.05] font-black tracking-tight sm:text-6xl">
              Dental care that fits around your week.
            </h1>
            <p className="rise rise-3 mt-6 max-w-xl text-lg leading-8 text-white/80">
              Check-ups, cleanings, aligners and implants across three Boston clinics, with evening hours in Quincy.
              Book, move and pay in the app, or ask Nora, our AI receptionist, at any hour and in eight languages.
            </p>
            <div className="rise rise-3 mt-8 flex flex-wrap gap-3">
              <Link href="#app" className="rounded-full bg-shine px-6 py-3 font-bold text-sea transition hover:bg-white">Get the app</Link>
              <Link href="/services" className="rounded-full border border-white/30 px-6 py-3 font-bold text-white transition hover:bg-white/10">See services and prices</Link>
            </div>
          </div>
          <div className="rise rise-3 self-end rounded-3xl bg-white/10 p-5 ring-1 ring-white/15 backdrop-blur">
            <div className="flex items-center gap-3">
              <Image src="/images/nora/speaking.png" alt="Nora, the AI receptionist" width={56} height={56} className="rounded-full bg-enamel" />
              <div>
                <p className="font-bold">Nora</p>
                <p className="text-xs text-white/70">AI receptionist · replies in your language</p>
              </div>
            </div>
            <div className="mt-4 space-y-2 text-sm">
              <p className="ml-auto w-fit max-w-[85%] rounded-2xl rounded-br-md bg-shine/90 px-3 py-2 text-sea">Is there a fee if I miss my appointment?</p>
              <p className="w-fit max-w-[90%] rounded-2xl rounded-bl-md bg-white px-3 py-2 text-sea">
                Our cancellation policy says a visit missed without 24 hours notice costs $50 at Back Bay and Cambridge. Quincy doesn&apos;t charge it.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Clinics */}
      <section id="clinics" className="mx-auto max-w-6xl scroll-mt-20 px-4 py-20 sm:px-6">
        <h2 className="font-display text-3xl font-black tracking-tight sm:text-4xl">Three clinics, one record</h2>
        <p className="mt-3 max-w-2xl text-muted">Your record, plans and payments follow you between clinics, so you can book wherever suits the day.</p>
        <div className="mt-10 grid gap-6 md:grid-cols-3">
          {locations.map((l) => (
            <article key={l.code} className="group overflow-hidden rounded-3xl border border-line bg-white shadow-sm transition hover:-translate-y-1 hover:shadow-lg">
              <div className="relative aspect-[4/3]">
                <Image src={`/images/clinics/${l.code}.jpg`} alt={`The ${l.name} clinic`} fill className="object-cover transition duration-500 group-hover:scale-105" sizes="(min-width: 768px) 33vw, 100vw" />
              </div>
              <div className="p-6">
                <h3 className="text-xl font-extrabold">{l.name}</h3>
                <p className="mt-1 text-sm text-muted">{l.address}, {l.city}, {l.state} {l.postal_code}</p>
                <ul className="mt-4 space-y-1 text-sm">{openingLines(l.hours).map((line) => <li key={line}>{line}</li>)}</ul>
                <p className="mt-4 text-sm text-muted">{ACCESS[l.code]}</p>
                <a href={`tel:${l.phone}`} className="mt-5 inline-block font-bold text-teal hover:underline">{phone(l.phone)}</a>
              </div>
            </article>
          ))}
        </div>
      </section>

      {/* Services */}
      <section className="bg-mist py-20">
        <div className="mx-auto max-w-6xl px-4 sm:px-6">
          <div className="flex flex-wrap items-end justify-between gap-4">
            <div>
              <h2 className="font-display text-3xl font-black tracking-tight sm:text-4xl">What we do</h2>
              <p className="mt-3 max-w-2xl text-muted">Clear prices for each clinic, before you book.</p>
            </div>
            <Link href="/services" className="font-bold text-teal hover:underline">All {services.length} services and prices</Link>
          </div>
          <div className="mt-10 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {featured.map((s) => {
              const prices = Object.values(s.prices);
              return (
                <Link key={s.code} href={`/services/${s.code}`} className="group overflow-hidden rounded-3xl bg-white shadow-sm ring-1 ring-line transition hover:-translate-y-1 hover:shadow-lg">
                  <div className="relative aspect-[16/9]">
                    <Image src={servicePicture(s.code)} alt="" fill className="object-cover" sizes="(min-width: 1024px) 33vw, 50vw" />
                  </div>
                  <div className="p-6">
                    <h3 className="text-lg font-extrabold group-hover:text-teal">{s.name}</h3>
                    <p className="mt-2 text-sm leading-6 text-muted">{s.summary}</p>
                    <p className="mt-4 text-sm font-semibold">
                      {prices.length ? `From ${money(Math.min(...prices))}` : "Price on request"} · {s.duration_minutes} minutes
                    </p>
                  </div>
                </Link>
              );
            })}
          </div>
        </div>
      </section>

      {/* Nora */}
      <section className="mx-auto grid max-w-6xl items-center gap-12 px-4 py-20 sm:px-6 md:grid-cols-2">
        <div className="relative mx-auto aspect-square w-full max-w-sm rounded-[2.5rem] bg-enamel">
          <Image src="/images/nora/idle.png" alt="Nora, the AI receptionist" fill className="object-contain p-8" sizes="384px" />
        </div>
        <div>
          <p className="text-sm font-bold text-teal">Meet Nora</p>
          <h2 className="mt-2 font-display text-3xl font-black tracking-tight sm:text-4xl">An AI receptionist that knows when to pass you to a person.</h2>
          <ul className="mt-6 space-y-3 text-muted">
            <li><b className="text-sea">Books, moves and cancels visits</b>, and nothing is booked until you press Confirm.</li>
            <li><b className="text-sea">Answers from our own policies</b>, and says which one, for fees, payment plans, insurance or parking.</li>
            <li><b className="text-sea">Speaks eight languages</b>: English, French, Dutch, German, Spanish, Italian, Lithuanian and Swedish.</li>
            <li><b className="text-sea">Never gives medical advice.</b> Anything about symptoms goes straight to a member of the Northgate team; urgent warning signs get emergency guidance at once.</li>
          </ul>
        </div>
      </section>

      {/* Team */}
      <section id="team" className="scroll-mt-20 bg-mist py-20">
        <div className="mx-auto max-w-6xl px-4 sm:px-6">
          <h2 className="font-display text-3xl font-black tracking-tight sm:text-4xl">The people you&apos;ll see</h2>
          <div className="mt-10 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {TEAM.map((p) => (
              <article key={p.name} className="flex gap-4 rounded-3xl bg-white p-5 ring-1 ring-line">
                <Image src={`/images/team/${p.photo}.jpg`} alt={p.name} width={88} height={88} className="size-22 shrink-0 rounded-2xl object-cover" />
                <div>
                  <h3 className="font-extrabold">{p.name}</h3>
                  <p className="text-sm font-semibold text-teal">{p.title}</p>
                  <p className="mt-2 text-sm leading-6 text-muted">{p.bio}</p>
                </div>
              </article>
            ))}
          </div>
        </div>
      </section>

      {/* App */}
      <section id="app" className="mx-auto max-w-6xl scroll-mt-20 px-4 py-20 sm:px-6">
        <div className="grid items-center gap-10 overflow-hidden rounded-[2.5rem] bg-gradient-to-br from-teal to-sea p-8 text-white sm:p-12 md:grid-cols-2">
          <div>
            <h2 className="font-display text-3xl font-black tracking-tight sm:text-4xl">Everything in one app</h2>
            <p className="mt-4 text-white/80">Book and move visits, pay securely, see your treatment plan and X-rays, join video consultations, and message the team.</p>
            <div className="mt-8 flex flex-wrap gap-3" aria-label="Download the app">
              <span className="rounded-xl bg-black px-5 py-3 text-sm font-semibold ring-1 ring-white/30">Google Play · coming soon</span>
              <span className="rounded-xl bg-black px-5 py-3 text-sm font-semibold ring-1 ring-white/30">App Store · coming soon</span>
            </div>
          </div>
          <ul className="grid grid-cols-2 gap-3 text-sm">
            {["Book in under a minute", "Pay with a secure link", "Video consultations", "Your X-rays and plans", "Reminders that let you reschedule", "Chat with Nora or the team"].map((t) => (
              <li key={t} className="rounded-2xl bg-white/10 p-4 font-semibold ring-1 ring-white/15">{t}</li>
            ))}
          </ul>
        </div>
      </section>

      {/* Contact */}
      <section id="contact" className="mx-auto grid max-w-6xl scroll-mt-20 gap-12 px-4 sm:px-6 md:grid-cols-[0.9fr_1.1fr]">
        <div>
          <h2 className="font-display text-3xl font-black tracking-tight sm:text-4xl">Ask us anything</h2>
          <p className="mt-3 text-muted">Not a patient yet? Send a question and the clinic you choose replies by email, usually the same working day.</p>
          <p className="mt-6 text-sm text-muted">For pain or an injury, call your clinic. For trouble breathing or swallowing, or swelling spreading to your eye or neck, call 911.</p>
        </div>
        <EnquiryForm locations={locations.map((l) => ({ code: l.code, name: l.name }))} services={services.map((s) => ({ code: s.code, name: s.name }))} />
      </section>
    </>
  );
}
