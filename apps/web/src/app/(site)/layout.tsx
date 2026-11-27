import Link from "next/link";
import Logo from "@/components/Logo";
import { Motion } from "@/components/Motion";

function Header() {
  return (
    <header className="sticky top-0 z-30 border-b border-line/70 bg-white/85 backdrop-blur">
      <nav className="mx-auto flex max-w-6xl items-center gap-6 px-4 py-3 sm:px-6" aria-label="Main">
        <Link href="/" className="flex items-center gap-2 font-extrabold tracking-tight text-sea">
          <Logo />
          Northgate Dental
        </Link>
        <div className="ml-auto hidden items-center gap-6 text-sm font-semibold text-muted md:flex">
          <Link href="/services" className="hover:text-teal">Services and prices</Link>
          <Link href="/#clinics" className="hover:text-teal">Clinics</Link>
          <Link href="/#team" className="hover:text-teal">Our team</Link>
          <Link href="/#contact" className="hover:text-teal">Contact</Link>
        </div>
        <Link href="/#app" className="ml-auto rounded-full bg-teal px-4 py-2 text-sm font-bold text-white shadow-sm transition hover:bg-teal-dark md:ml-0">
          Book in the app
        </Link>
      </nav>
    </header>
  );
}

function Footer() {
  return (
    <footer className="mt-24 bg-sea text-white/80">
      <div className="mx-auto grid max-w-6xl gap-10 px-4 py-14 sm:px-6 md:grid-cols-4">
        <div className="md:col-span-2">
          <p className="text-lg font-extrabold text-white">Northgate Dental</p>
          <p className="mt-3 max-w-sm text-sm leading-6">
            Family dentistry at Back Bay, Cambridge and Quincy. A fictional practice built as a portfolio project: the
            people, clinics and records are made up, and no real patient data is used.
          </p>
        </div>
        <div className="text-sm leading-7">
          <p className="font-bold text-white">Patients</p>
          <Link href="/services" className="block hover:text-white">Services and prices</Link>
          <Link href="/#app" className="block hover:text-white">The Northgate app</Link>
          <Link href="/#contact" className="block hover:text-white">Send us a question</Link>
        </div>
        <div className="text-sm leading-7">
          <p className="font-bold text-white">Team</p>
          <Link href="/portal" className="block hover:text-white">Staff portal</Link>
          <p className="mt-3 text-xs text-white/60">In an emergency call 911.</p>
        </div>
      </div>
    </footer>
  );
}

export default function SiteLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <a href="#main" className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50 focus:rounded focus:bg-white focus:p-2">Skip to content</a>
      <Header />
      <main id="main">{children}</main>
      <Motion />
      <Footer />
    </>
  );
}
