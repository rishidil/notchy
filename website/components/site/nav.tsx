import Image from "next/image";
import { Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { GitHubIcon } from "@/components/site/icons";
import { SITE, asset } from "@/lib/site";

const links = [
  { href: "#features", label: "Features" },
  { href: "#agents", label: "Agents" },
  { href: "#customize", label: "Customize" },
  { href: "#download", label: "Download" },
  { href: "#faq", label: "FAQ" },
];

export function Nav() {
  return (
    <header className="sticky top-0 z-50 w-full border-b border-white/[0.06] bg-[#060608]/70 backdrop-blur-xl supports-[backdrop-filter]:bg-[#060608]/55">
      <div className="mx-auto flex h-16 max-w-6xl items-center gap-6 px-4 sm:px-6">
        <a href="#top" className="flex items-center gap-2.5 font-semibold tracking-tight">
          <Image
            src={asset("/icon-96.png")}
            alt=""
            width={32}
            height={32}
            loading="eager"
            fetchPriority="high"
            className="size-8 drop-shadow-[0_4px_12px_rgb(191_89_255/0.35)]"
          />
          <span>{SITE.name}</span>
        </a>

        <nav className="hidden items-center gap-1 text-sm text-muted-foreground md:flex">
          {links.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="rounded-full px-3 py-1.5 transition-colors hover:bg-white/[0.05] hover:text-foreground"
            >
              {l.label}
            </a>
          ))}
          <a
            href={SITE.githubUrl}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 transition-colors hover:bg-white/[0.05] hover:text-foreground"
          >
            <GitHubIcon className="size-4" />
            GitHub
          </a>
        </nav>

        <div className="ml-auto flex items-center gap-2">
          <Button
            asChild
            variant="ghost"
            size="icon"
            className="rounded-full md:hidden"
          >
            <a href={SITE.githubUrl} target="_blank" rel="noreferrer" aria-label="GitHub">
              <GitHubIcon className="size-4" />
            </a>
          </Button>
          <Button asChild size="sm" className="h-8 rounded-full px-3.5 font-medium pointer-coarse:hidden">
            <a href={SITE.downloadUrl}>
              <Download data-icon="inline-start" />
              Download
            </a>
          </Button>
        </div>
      </div>
    </header>
  );
}
