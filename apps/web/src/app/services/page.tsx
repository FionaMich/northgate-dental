import type { Metadata } from "next";
import Image from "next/image";
import { catalogue, money, servicePicture } from "@/lib/data";

export const metadata: Metadata = { title: "Services and prices" };

export default async function Services() {
  const { locations, services } = await catalogue();
  return (
    <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
      <h1 className="font-display text-4xl font-black tracking-tight sm:text-5xl">Services and prices</h1>
      <p className="mt-4 max-w-2xl text-muted">
        Prices are the self-pay price at each clinic. With insurance we bill your plan directly and give you a written
        estimate before larger treatment.
      </p>
      <div className="mt-12 space-y-6">
        {services.map((s) => (
          <article key={s.code} id={s.code} className="grid scroll-mt-24 gap-6 overflow-hidden rounded-3xl bg-white ring-1 ring-line md:grid-cols-[220px_1fr]">
            <div className="relative aspect-[16/9] md:aspect-auto">
              <Image src={servicePicture(s.code)} alt="" fill className="object-cover" sizes="(min-width: 768px) 220px, 100vw" />
            </div>
            <div className="p-6 md:pl-0">
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <h2 className="text-xl font-extrabold">{s.name}</h2>
                <p className="text-sm text-muted">{s.duration_minutes} minutes</p>
              </div>
              <p className="mt-2 leading-7 text-muted">{s.summary}</p>
              <dl className="mt-5 grid grid-cols-3 gap-3 text-sm">
                {locations.map((l) => (
                  <div key={l.code} className="rounded-2xl bg-mist px-4 py-3">
                    <dt className="text-muted">{l.name}</dt>
                    <dd className={s.prices[l.code] != null ? "text-lg font-extrabold" : "mt-1 text-muted"}>
                      {s.prices[l.code] != null ? money(s.prices[l.code]) : "Not here"}
                    </dd>
                  </div>
                ))}
              </dl>
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}
