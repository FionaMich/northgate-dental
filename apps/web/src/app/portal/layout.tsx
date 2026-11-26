// The staff portal has its own chrome (the clinical workspace), not the public site's header and footer.
export default function PortalLayout({ children }: { children: React.ReactNode }) {
  return <main id="main" className="min-h-screen bg-[#f4f7f7]">{children}</main>;
}
