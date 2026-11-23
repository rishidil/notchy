import { Download, Laptop, Terminal } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { CopyButton } from "@/components/site/copy-button";
import { GitHubIcon } from "@/components/site/icons";
import { SectionHeading } from "@/components/site/section-heading";
import { SITE } from "@/lib/site";

const steps = [
  {
    title: "Download the DMG",
    body: (
      <>
        Grab <span className="font-mono text-[0.9em] text-foreground/90">Notchy.dmg</span>,
        the latest release from GitHub.
      </>
    ),
  },
  {
    title: "Drag to Applications",
    body: (
      <>
        Open the disk image and drag <b className="font-medium text-foreground">Notchy</b>{" "}
        onto the <b className="font-medium text-foreground">Applications</b> folder.
      </>
    ),
  },
  {
    title: "Open it",
    body: (
      <>
        macOS will say it &ldquo;could not verify&rdquo; the app. That&rsquo;s expected —
        click <b className="font-medium text-foreground">Done</b>.
      </>
    ),
  },
  {
    title: "Open Anyway",
    body: (
      <>
        <b className="font-medium text-foreground">System Settings → Privacy &amp; Security</b>,
        scroll down and click <b className="font-medium text-foreground">Open Anyway</b>. One time
        only.
      </>
    ),
  },
];

export function Install() {
  return (
    <section id="download" className="relative py-20 sm:py-28">
      <div className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-[600px] bg-[radial-gradient(45%_50%_at_50%_0%,rgb(92_107_255/0.16),transparent)]" />
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <SectionHeading
          eyebrow="Download"
          title={
            <>
              Up and running in <span className="text-brand">four steps.</span>
            </>
          }
          description="No Terminal needed. Notchy is free, with no account, no subscription and no ads."
        />

        <ol className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {steps.map((s, i) => (
            <li key={s.title} className="reveal">
              <Card className="relative h-full bg-white/[0.025] ring-white/[0.07] [--card-spacing:--spacing(5)]">
                <CardContent className="flex flex-col gap-3">
                  <span className="bg-brand grid size-9 place-items-center rounded-full text-sm font-semibold text-black">
                    {i + 1}
                  </span>
                  <h3 className="mt-1 text-base font-semibold">{s.title}</h3>
                  <p className="text-[14px] leading-relaxed text-muted-foreground">{s.body}</p>
                </CardContent>
              </Card>
            </li>
          ))}
        </ol>

        <div className="reveal mt-10 flex flex-col items-center gap-4 text-center">
          <Button
            asChild
            size="lg"
            className="cta-glow h-12 rounded-full px-7 text-base font-semibold"
          >
            <a href={SITE.downloadUrl}>
              <Download className="size-5" />
              Download for Mac — Free
            </a>
          </Button>
          <p className="text-xs text-muted-foreground/80">
            {SITE.requirements} ·{" "}
            <a
              href={SITE.releasesUrl}
              target="_blank"
              rel="noreferrer"
              className="underline-offset-4 hover:text-foreground hover:underline"
            >
              All releases
            </a>
          </p>
        </div>

        <div className="mt-16 grid items-start gap-4 lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]">
          <Card className="reveal bg-white/[0.025] ring-white/[0.07] [--card-spacing:--spacing(5)]">
            <CardContent className="flex h-full gap-4">
              <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-[#59d9ff]/10 text-[#59d9ff]">
                <Laptop className="size-5" />
              </span>
              <div>
                <h3 className="font-semibold">No notch? No problem.</h3>
                <p className="mt-1.5 text-[14px] leading-relaxed text-muted-foreground">
                  Works on Macs without a notch too — the island hides until it has something to
                  show. Push your cursor to the top center of the screen to open it.
                </p>
              </div>
            </CardContent>
          </Card>

          <Card className="reveal bg-white/[0.025] ring-white/[0.07] [--card-spacing:--spacing(5)]">
            <CardContent className="flex flex-col gap-4">
              <div className="flex gap-4">
                <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-[#bf59ff]/10 text-[#bf59ff]">
                  <Terminal className="size-5" />
                </span>
                <div className="min-w-0">
                  <h3 className="font-semibold">Build from source</h3>
                  <p className="mt-1.5 text-[14px] leading-relaxed text-muted-foreground">
                    Needs the Xcode Command Line Tools. Builds, installs to /Applications and
                    launches.
                  </p>
                </div>
              </div>
              <Separator className="bg-white/[0.06]" />
              <div className="flex items-start gap-2 rounded-lg border border-white/[0.08] bg-black/50 py-2 pl-3.5 pr-1.5">
                <code className="min-w-0 flex-1 whitespace-pre-wrap py-1 font-mono text-[12.5px] leading-relaxed text-foreground/90 [overflow-wrap:anywhere]">
                  <span className="select-none text-muted-foreground">$ </span>
                  {SITE.buildCommand}
                </code>
                <CopyButton text={SITE.buildCommand} />
              </div>
              <a
                href={SITE.githubUrl}
                target="_blank"
                rel="noreferrer"
                className="inline-flex w-fit items-center gap-1.5 text-[13px] text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
              >
                <GitHubIcon className="size-3.5" />
                rishidil/notchy
              </a>
            </CardContent>
          </Card>
        </div>
      </div>
    </section>
  );
}
