"use client";
// The staff portal. Everything runs in the browser with the staff member's own session: row level security decides
// what they see (their clinics only) and the staff gate refuses every row until they have passed two-factor sign-in.
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import Logo from "@/components/Logo";
import { Workspace } from "@/components/portal/Workspace";
import { supabase } from "@/lib/supabase";

type Stage = "loading" | "signin" | "mfa" | "enrol" | "ready";

const card = "rounded-md bg-white p-7 shadow-xl";
const input = "mt-1 w-full rounded-md border border-line px-4 py-3 outline-none focus:border-teal focus:ring-4 focus:ring-enamel";
const button = "w-full rounded-md bg-teal px-5 py-2.5 font-bold text-white transition hover:bg-teal-dark disabled:opacity-60";

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
        <p className="rounded-md bg-enamel px-4 py-3 text-sm">Just looking? <Link href="/portal/demo" className="font-bold text-teal underline">Explore the portal with sample data</Link>, no sign-in needed.</p>
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
  return <Workspace onSignOut={async () => { await supabase.auth.signOut(); setStage("signin"); }} />;
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-sea">
      <div className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-4 py-12">
        <Link href="/" className="mb-6 flex items-center gap-2.5 text-white">
          <Logo className="size-8" />
          <span className="text-lg font-bold">Northgate <span className="font-normal text-white/60">Workspace</span></span>
        </Link>
        {children}
        <p className="mt-6 text-center text-xs text-white/50">For Northgate Dental staff. Access is logged and audited.</p>
      </div>
    </div>
  );
}
