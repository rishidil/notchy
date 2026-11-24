export const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

/** Prefix a path in /public with the GitHub Pages base path. */
export function asset(path: string): string {
  return `${BASE_PATH}${path.startsWith("/") ? path : `/${path}`}`;
}

export const SITE = {
  name: "Notchy",
  url: "https://rishidil.github.io/notchy/",
  description:
    "The AI notch for your Mac. Ask Claude anything, drop files on the notch to ask about them, and answer your coding agents, alongside music, calendar, weather and more. Free and open source.",
  downloadUrl:
    "https://github.com/rishidil/notchy/releases/latest/download/Notchy.dmg",
  githubUrl: "https://github.com/rishidil/notchy",
  releasesUrl: "https://github.com/rishidil/notchy/releases",
  licenseUrl: "https://github.com/rishidil/notchy/blob/main/LICENSE",
  requirements: "Requires macOS 14+ · Apple silicon",
  buildCommand:
    "git clone https://github.com/rishidil/notchy.git && cd notchy && ./build.sh install",
} as const;
