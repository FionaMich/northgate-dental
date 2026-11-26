// The Northgate mark: a tooth drawn as a gate, with the north notch at the top. Inline SVG, no image request.
export default function Logo({ className = "size-8" }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" className={className} aria-hidden="true">
      <rect width="32" height="32" rx="9" fill="#137c6c" />
      <path d="M9.5 9.5c0-1.6 1.3-2.8 2.9-2.6 1.3.2 2.3.9 3.6.9s2.3-.7 3.6-.9c1.6-.2 2.9 1 2.9 2.6 0 3.2-.9 5.1-1.5 7.6-.5 2.2-.8 5.9-2.4 5.9-1.3 0-1.4-3.6-2.6-3.6s-1.3 3.6-2.6 3.6c-1.6 0-1.9-3.7-2.4-5.9-.6-2.5-1.5-4.4-1.5-7.6Z"
        fill="#fff" />
      <path d="m16 4.2 1.6 2.3h-3.2z" fill="#1fbfa2" />
    </svg>
  );
}
