import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";

// Fonts are bundled with the site (the same files as the app); nothing is loaded from a font service.
const jakarta = localFont({
  variable: "--font-jakarta",
  src: [
    { path: "../fonts/PlusJakartaSans-Regular.ttf", weight: "400" },
    { path: "../fonts/PlusJakartaSans-Medium.ttf", weight: "500" },
    { path: "../fonts/PlusJakartaSans-SemiBold.ttf", weight: "600" },
    { path: "../fonts/PlusJakartaSans-Bold.ttf", weight: "700" },
    { path: "../fonts/PlusJakartaSans-ExtraBold.ttf", weight: "800" },
  ],
});
const lato = localFont({ variable: "--font-lato", src: [{ path: "../fonts/Lato-Black.ttf", weight: "900" }] });

export const metadata: Metadata = {
  title: { default: "Northgate Dental: Back Bay, Cambridge and Quincy", template: "%s · Northgate Dental" },
  description: "Family dentistry in Boston, Cambridge and Quincy. Book, move or pay in the app, or ask Nora, our AI receptionist, any time.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${jakarta.variable} ${lato.variable}`}>
      <body className="font-sans">
        {children}
      </body>
    </html>
  );
}
