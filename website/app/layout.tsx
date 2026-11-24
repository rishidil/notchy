import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { SITE, asset } from "@/lib/site";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  metadataBase: new URL(SITE.url),
  title: "Notchy — The AI notch for your Mac",
  description: SITE.description,
  applicationName: SITE.name,
  // Paths in /public are not basePath-aware in metadata, so prefix them.
  icons: {
    icon: [{ url: asset("/icon.png"), type: "image/png" }],
    apple: [{ url: asset("/icon.png") }],
  },
  keywords: [
    "MacBook notch",
    "Dynamic Island",
    "macOS",
    "menu bar",
    "now playing",
    "open source",
  ],
  openGraph: {
    type: "website",
    url: SITE.url,
    siteName: SITE.name,
    title: "Notchy — The AI notch for your Mac",
    description: SITE.description,
    images: [{ url: `${SITE.url}icon.png`, width: 1024, height: 1024 }],
  },
  twitter: {
    card: "summary",
    title: "Notchy",
    description: SITE.description,
    images: [`${SITE.url}icon.png`],
  },
};

export const viewport: Viewport = {
  themeColor: "#060608",
  colorScheme: "dark",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`dark ${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col overflow-x-clip">{children}</body>
    </html>
  );
}
