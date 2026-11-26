"use client";
import { useState } from "react";
import { supabase } from "@/lib/supabase";

type Option = { code: string; name: string };

export default function EnquiryForm({ locations, services }: { locations: Option[]; services: Option[] }) {
  const [state, setState] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [error, setError] = useState("");

  async function submit(form: FormData) {
    if (form.get("website")) return setState("sent"); // the hidden field: only bots fill it in
    setState("sending");
    const { error } = await supabase.rpc("submit_lead", {
      name: String(form.get("name") ?? ""),
      email: String(form.get("email") ?? ""),
      phone: String(form.get("phone") ?? "") || null,
      location_code: String(form.get("location") ?? ""),
      service_code: String(form.get("service") ?? "") || null,
      message: String(form.get("message") ?? ""),
      consent: form.get("consent") === "on",
    });
    if (error) {
      setError(error.code === "54000" ? "We already have your questions from today; the clinic will reply soon." : "Please check your details and try again, or call the clinic.");
      return setState("error");
    }
    setState("sent");
  }

  if (state === "sent") {
    return (
      <div role="status" className="rounded-3xl bg-enamel p-8">
        <p className="text-xl font-extrabold">Thank you, we have your question.</p>
        <p className="mt-2 text-muted">The clinic will reply by email, usually the same working day.</p>
      </div>
    );
  }

  const field = "mt-1 w-full rounded-xl border border-line bg-white px-4 py-3 outline-none transition focus:border-teal focus:ring-4 focus:ring-enamel";
  return (
    <form action={submit} className="grid gap-4 rounded-3xl bg-white p-6 ring-1 ring-line sm:grid-cols-2 sm:p-8">
      <label className="text-sm font-semibold">Name<input name="name" required minLength={2} maxLength={80} autoComplete="name" className={field} /></label>
      <label className="text-sm font-semibold">Email<input name="email" type="email" required maxLength={120} autoComplete="email" className={field} /></label>
      <label className="text-sm font-semibold">Phone <span className="font-normal text-muted">(optional)</span><input name="phone" type="tel" maxLength={30} autoComplete="tel" className={field} /></label>
      <label className="text-sm font-semibold">Clinic
        <select name="location" required className={field} defaultValue="">
          <option value="" disabled>Choose a clinic</option>
          {locations.map((l) => <option key={l.code} value={l.code}>{l.name}</option>)}
        </select>
      </label>
      <label className="text-sm font-semibold sm:col-span-2">About <span className="font-normal text-muted">(optional)</span>
        <select name="service" className={field} defaultValue="">
          <option value="">Something else</option>
          {services.map((s) => <option key={s.code} value={s.code}>{s.name}</option>)}
        </select>
      </label>
      <label className="text-sm font-semibold sm:col-span-2">Your question
        <textarea name="message" required minLength={2} maxLength={1000} rows={4} className={field} placeholder="No medical details, please: the clinic will ask what it needs." />
      </label>
      <input name="website" tabIndex={-1} autoComplete="off" aria-hidden className="hidden" />
      <label className="flex gap-3 text-sm text-muted sm:col-span-2">
        <input name="consent" type="checkbox" required className="mt-1 size-4 accent-teal" />
        Northgate Dental may contact me by email or phone about this question. We keep it for 12 months, then delete it.
      </label>
      {state === "error" && <p role="alert" className="text-sm font-semibold text-danger sm:col-span-2">{error}</p>}
      <button disabled={state === "sending"} className="rounded-full bg-teal px-6 py-3 font-bold text-white transition hover:bg-teal-dark disabled:opacity-60 sm:col-span-2 sm:justify-self-start">
        {state === "sending" ? "Sending…" : "Send my question"}
      </button>
    </form>
  );
}
