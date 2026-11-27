"use client";
// The staff portal with sample data, for anyone to try: no sign-in, no database. See src/lib/demoDb.ts.
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo } from "react";
import { DbContext, Workspace } from "@/components/portal/Workspace";
import { demoDb } from "@/lib/demoDb";

export default function PortalDemo() {
  const db = useMemo(() => demoDb(), []);
  const router = useRouter();
  return (
    <>
      <div className="border-b border-apricot/40 bg-apricot/15">
        <p className="mx-auto max-w-7xl px-4 py-2.5 text-sm sm:px-6">
          <b>Demo with sample data.</b> The people and visits are invented, and nothing you change is saved.
          Northgate staff sign in at <Link href="/portal" className="font-bold text-teal underline">the real portal</Link> with
          a password and an authenticator code.
        </p>
      </div>
      <DbContext.Provider value={db}>
        <Workspace onSignOut={() => router.push("/")} />
      </DbContext.Provider>
    </>
  );
}
