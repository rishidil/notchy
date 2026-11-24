import { Cpu, FileText, Radio, Sparkle } from "lucide-react";
import { Screenshot } from "@/components/site/screenshot";
import { SectionHeading } from "@/components/site/section-heading";
import { asset } from "@/lib/site";

const claude = "#d97757";

const engines = [
  {
    icon: Cpu,
    color: "#59d9ff",
    name: "On your Mac",
    tag: "Free · private · offline",
    text: "Quick questions are answered by Apple's built-in model, right on your Mac. Nothing is sent anywhere, and there's nothing to pay or sign up for.",
  },
  {
    icon: Sparkle,
    color: claude,
    name: "Claude, on your plan",
    tag: "Through T3 Code",
    text: "Files and bigger questions go to Claude through T3 Code, using the Claude subscription you already have. Every chat is saved as a thread in T3 Code.",
  },
  {
    icon: Sparkle,
    color: claude,
    name: "Claude API",
    tag: "Bring your own key",
    text: "Prefer the API? Connect an Anthropic API key for Claude with web search and cited sources, billed by Anthropic.",
  },
];

const points = [
  {
    icon: FileText,
    title: "Drop files, ask questions",
    text: "Drag a PDF, screenshot, code file or a whole folder onto the notch and drop it on Ask AI. Then just ask.",
  },
  {
    icon: Radio,
    title: "Ask, then keep working",
    text: "Close the notch and carry on. It shows the AI thinking, searching and writing, and pops up when the answer's ready.",
  },
];

export function Claude() {
  return (
    <section id="ai" className="relative py-20 sm:py-28">
      <div className="pointer-events-none absolute inset-x-0 top-1/4 -z-10 h-[520px] bg-[radial-gradient(50%_50%_at_70%_50%,rgb(217_119_87/0.16),transparent)]" />
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <SectionHeading
          eyebrow="New in 1.4 · AI"
          title={
            <>
              Ask anything, <span style={{ color: claude }}>right from your notch.</span>
            </>
          }
          description="No browser tab, no app switching. Quick questions are answered free on your Mac; files and harder questions go to Claude. You pick, or let Notchy decide."
        />
        <div className="reveal mt-12 grid gap-4 lg:grid-cols-5">
          <Screenshot
            file="claude.webp"
            alt="The AI tab answering a question about an attached PDF with Claude"
            width={1560}
            height={708}
            aspect="aspect-[1560/708]"
            className="lg:col-span-3"
          />
          <div className="grid gap-4 lg:col-span-2">
            <Screenshot
              file="ai-quick.webp"
              alt="A quick question answered by Apple's on-device model"
              width={1560}
              height={708}
              aspect="aspect-[1560/708]"
            />
            <Screenshot
              file="claude-live.webp"
              alt="A live activity showing Claude searching the web"
              width={1560}
              height={520}
              aspect="aspect-[3/1]"
            />
          </div>
        </div>
        <ul className="mt-12 grid gap-4 lg:grid-cols-3">
          {engines.map((e) => (
            <li key={e.name} className="reveal rounded-2xl border border-white/[0.08] bg-white/[0.025] p-5">
              <div className="flex items-center gap-2">
                <e.icon className="size-5" style={{ color: e.color }} />
                <span className="text-xs font-medium text-muted-foreground">{e.tag}</span>
              </div>
              <h3 className="mt-4 font-semibold">{e.name}</h3>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{e.text}</p>
            </li>
          ))}
        </ul>
        <ul className="mt-4 grid gap-4 sm:grid-cols-2">
          {points.map((p) => (
            <li key={p.title} className="reveal rounded-2xl border border-white/[0.08] bg-white/[0.025] p-5">
              <p.icon className="size-5" style={{ color: claude }} />
              <h3 className="mt-4 font-semibold">{p.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{p.text}</p>
            </li>
          ))}
        </ul>
        <p className="reveal mt-6 text-center text-xs text-muted-foreground/80">
          On-device answers need macOS 26 with Apple Intelligence. Curious how it works?{" "}
          <a href={asset("/docs/#ai")} className="text-foreground underline-offset-4 hover:underline">
            Read the developer docs
          </a>
          .
        </p>
      </div>
    </section>
  );
}
