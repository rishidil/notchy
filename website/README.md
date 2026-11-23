# Notchy website

Next.js (App Router) + Tailwind CSS v4 + shadcn/ui, exported as a static site for GitHub Pages at
https://rishidil.github.io/notchy/.

```bash
npm install
npm run dev     # http://localhost:3000/notchy/
npm run build   # static export to out/
```

- Screenshots live in `public/screenshots/` (feature shots ~1520x520, `settings.png` ~1400x1000).
  Replace the placeholder PNGs with the same file names.
- Everything is served under the `/notchy` base path (set in `next.config.ts`). Reference files in
  `public/` with `asset("/path")` from `lib/site.ts`, never a bare `/path`.
