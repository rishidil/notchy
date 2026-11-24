import { MacOnlyNotice } from "@/components/site/mac-only";
import { ArrowRight, Download } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { GitHubIcon } from "@/components/site/icons";
import { NotchMockup } from "@/components/site/notch-mockup";
import { SITE } from "@/lib/site";

export function Hero() {
  return (
    <section id="top" className="relative isolate overflow-hidden pt-16 sm:pt-24">
      {/* Background glow */}
      <div className="pointer-events-none absolute inset-0 -z-10">
        <div className="absolute left-1/2 top-[-20%] h-[640px] w-[1100px] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,rgb(92_107_255/0.28),transparent)]" />
        <div className="absolute left-[15%] top-[10%] h-[380px] w-[480px] rounded-full bg-[radial-gradient(closest-side,rgb(89_217_255/0.12),transparent)]" />
        <div className="absolute right-[10%] top-[18%] h-[380px] w-[480px] rounded-full bg-[radial-gradient(closest-side,rgb(255_97_158/0.12),transparent)]" />
        <div className="bg-grid absolute inset-0 [mask-image:radial-gradient(ellipse_at_top,black_20%,transparent_70%)]" />
      </div>

      <div className="mx-auto flex max-w-6xl flex-col items-center px-4 text-center sm:px-6">
        <a
          href={SITE.githubUrl}
          target="_blank"
          rel="noreferrer"
          className="rise group"
        >
          <Badge
            variant="outline"
            className="h-7 gap-2 rounded-full border-white/10 bg-white/[0.04] px-3 text-xs text-muted-foreground transition-colors group-hover:border-white/20 group-hover:text-foreground"
          >
            <span className="size-1.5 rounded-full bg-[#d97757]" />
            New in 1.4: AI in your notch, with Claude · Free &amp; open source
            <ArrowRight className="transition-transform group-hover:translate-x-0.5" />
          </Badge>
        </a>

        <h1
          className="rise-move mt-6 max-w-4xl text-balance text-[2.6rem] font-semibold leading-[1.05] tracking-[-0.035em] sm:text-7xl"
          style={{ animationDelay: "80ms" }}
        >
          The AI notch <span className="text-brand">for your Mac.</span>
        </h1>

        <p
          className="rise mt-6 max-w-2xl text-pretty text-lg leading-relaxed text-muted-foreground sm:text-xl"
          style={{ animationDelay: "160ms" }}
        >
          {SITE.description}
        </p>

        <div
          className="rise mt-9 flex w-full flex-col items-center justify-center gap-3 sm:w-auto sm:flex-row"
          style={{ animationDelay: "240ms" }}
        >
          <Button
            asChild
            size="lg"
            className="cta-glow h-12 w-full rounded-full px-7 text-base font-semibold pointer-coarse:hidden sm:w-auto"
          >
            <a href={SITE.downloadUrl}>
              <Download className="size-5" />
              Download for Mac — Free
            </a>
          </Button>
          <Button
            asChild
            size="lg"
            variant="outline"
            className="h-12 w-full rounded-full border-white/15 bg-white/[0.03] px-6 text-base font-medium hover:bg-white/[0.07] sm:w-auto"
          >
            <a href={SITE.githubUrl} target="_blank" rel="noreferrer">
              <GitHubIcon className="size-5" />
              View on GitHub
            </a>
          </Button>
        </div>
        <MacOnlyNotice className="rise mt-6 hidden pointer-coarse:flex" />

        <p
          className="rise mt-4 text-xs text-muted-foreground/80"
          style={{ animationDelay: "320ms" }}
        >
          {SITE.requirements}
          <span className="pointer-coarse:hidden">
            {" · "}
            <a href="#first-launch" className="underline-offset-4 hover:text-foreground hover:underline">
              First time? How to open it
            </a>
          </span>
        </p>
      </div>

      <div
        className="rise mx-auto mt-14 max-w-6xl px-3 sm:mt-20 sm:px-6"
        style={{ animationDelay: "400ms" }}
      >
        <NotchMockup />
      </div>
    </section>
  );
}
