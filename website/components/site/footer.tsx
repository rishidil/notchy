import Image from "next/image";
import { Heart } from "lucide-react";
import { Separator } from "@/components/ui/separator";
import { GitHubIcon } from "@/components/site/icons";
import { SITE, asset } from "@/lib/site";

export function Footer() {
  return (
    <footer className="relative mt-8 border-t border-white/[0.06]">
      <div className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
        <div className="flex flex-col items-start justify-between gap-8 sm:flex-row sm:items-center">
          <div className="flex items-center gap-3">
            <Image src={asset("/icon-128.png")} alt="" width={36} height={36} className="size-9" />
            <div>
              <div className="font-semibold tracking-tight">{SITE.name}</div>
              <div className="text-sm text-muted-foreground">A Dynamic Island for your MacBook.</div>
            </div>
          </div>
          <nav className="flex flex-wrap items-center gap-x-6 gap-y-2 text-sm text-muted-foreground">
            <a href="#features" className="hover:text-foreground">Features</a>
            <a href="#customize" className="hover:text-foreground">Customize</a>
            <a href="#download" className="hover:text-foreground">Download</a>
            <a href="#faq" className="hover:text-foreground">FAQ</a>
            <a
              href={SITE.githubUrl}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1.5 hover:text-foreground"
            >
              <GitHubIcon className="size-4" />
              GitHub
            </a>
          </nav>
        </div>
        <Separator className="my-8 bg-white/[0.06]" />
        <div className="flex flex-col justify-between gap-3 text-xs text-muted-foreground sm:flex-row">
          <p>
            Released under the{" "}
            <a
              href={SITE.licenseUrl}
              target="_blank"
              rel="noreferrer"
              className="underline underline-offset-4 hover:text-foreground"
            >
              MIT License
            </a>
            . Not affiliated with Apple Inc.
          </p>
          <p className="inline-flex items-center gap-1.5">
            Made for the Mac <Heart className="size-3 fill-[#ff619e] text-[#ff619e]" />
          </p>
        </div>
      </div>
    </footer>
  );
}
