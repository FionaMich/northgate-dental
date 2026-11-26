import type { NextConfig } from "next";

// A static site for Cloudflare Pages: every page is built ahead of time; the portal talks to Supabase from the browser.
const nextConfig: NextConfig = {
  output: "export",
  images: { unoptimized: true },
  trailingSlash: true,
};

export default nextConfig;
