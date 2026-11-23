import type { NextConfig } from "next";

// On GitHub Pages the site lives at https://rishidil.github.io/notchy/, so everything sits under /notchy.
// On a custom domain (served from the root) set this to "" — or build with BASE_PATH="".
const basePath = process.env.BASE_PATH ?? "/notchy";

const nextConfig: NextConfig = {
  output: "export",
  basePath,
  trailingSlash: true,
  images: { unoptimized: true },
  env: {
    NEXT_PUBLIC_BASE_PATH: basePath,
  },
  turbopack: {
    // Build from this folder even though a lockfile exists higher up.
    root: process.cwd(),
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
