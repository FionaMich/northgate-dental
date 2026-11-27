// Store badges for the Northgate app (Fiona's decisions, 2026-11-27: shown as available, and they open the app's
// release page, where the signed Android APK, its checksum and the demo notice are; there is no store listing yet).
const APP = "https://github.com/FionaMich/northgate-dental/releases/tag/app-v0.3.0";

function Badge({ href, small, big, children }: { href: string; small: string; big: string; children: React.ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noopener noreferrer"
      className="inline-flex h-14 items-center gap-3 rounded-xl bg-black px-4 text-white ring-1 ring-white/25 transition hover:bg-[#111] focus-visible:ring-2 focus-visible:ring-shine">
      {children}
      <span className="leading-tight">
        <span className="block text-[11px] font-medium text-white/80">{small}</span>
        <span className="block text-[19px] font-semibold tracking-tight">{big}</span>
      </span>
    </a>
  );
}

export default function StoreBadges() {
  return (
    <div className="flex flex-wrap gap-3" aria-label="Download the Northgate app">
      <Badge href={APP} small="Download on the" big="App Store">
        <svg viewBox="0 0 24 24" className="size-7" fill="currentColor" aria-hidden>
          <path d="M16.4 12.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.8-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.4-.9-1.7 0-3.3 1-4.2 2.6-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8s2 .8 3.4.8c1.4 0 2.3-1.3 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9 0 0-2.6-1-2.6-4.1zM13.9 4.9c.7-.9 1.2-2 1-3.2-1 .1-2.3.7-3 1.6-.7.8-1.3 2-1.1 3.1 1.2.1 2.3-.6 3.1-1.5z" />
        </svg>
      </Badge>
      <Badge href={APP} small="Get it on" big="Google Play">
        <svg viewBox="0 0 24 24" className="size-7" aria-hidden>
          <path d="M3.6 2.3 13.4 12l-9.8 9.7c-.4-.2-.6-.6-.6-1.1V3.4c0-.5.2-.9.6-1.1z" fill="#00d7fe" />
          <path d="m16.7 8.7-3.3 3.3-9.8-9.7c.2-.1.5-.1.8 0l12.3 6.4z" fill="#00f076" />
          <path d="m16.7 15.3-12.3 6.4c-.3.1-.6.1-.8 0l9.8-9.7 3.3 3.3z" fill="#ff3a44" />
          <path d="m20.4 12-3.7 3.3-3.3-3.3 3.3-3.3 3.1 1.6c.9.5.9 1.6.6 1.7z" fill="#ffd400" />
        </svg>
      </Badge>
    </div>
  );
}
