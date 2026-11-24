import { FileText, Globe, KeyRound, Radio } from "lucide-react";
import { Screenshot } from "@/components/site/screenshot";
import { SectionHeading } from "@/components/site/section-heading";

const claude = "#d97757";

const points = [
  {
    icon: FileText,
    title: "Drop files, ask questions",
    text: "Drag a PDF, screenshot, spreadsheet export, code file or whole folder onto the notch and drop it on Ask Claude. Then just ask.",
  },
  {
    icon: Globe,
    title: "Current answers, with sources",
    text: "Claude searches the web when a question needs it and shows where each answer came from, one click away.",
  },
  {
    icon: Radio,
    title: "Ask, then keep working",
    text: "Close the notch and carry on. It shows Claude thinking, searching and writing, and pops up when the answer's ready.",
  },
  {
    icon: KeyRound,
    title: "Your account, your key",
    text: "Connect your own Anthropic API key once. It stays in your Mac's keychain, and only what you ask is sent to Claude.",
  },
];

export function Claude() {
  return (
    <section id="claude" className="relative py-20 sm:py-28">
      <div className="pointer-events-none absolute inset-x-0 top-1/4 -z-10 h-[520px] bg-[radial-gradient(50%_50%_at_70%_50%,rgb(217_119_87/0.16),transparent)]" />
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <SectionHeading
          eyebrow="New in 1.4 · Claude"
          title={
            <>
              Claude, <span style={{ color: claude }}>right in your notch.</span>
            </>
          }
          description="Ask anything from the top of your screen without opening a browser tab or an app. Answers stream in while you work, and anything you drop on the notch can come along as context."
        />
        <div className="reveal mt-12 grid gap-4 lg:grid-cols-5">
          <Screenshot
            file="claude.webp"
            alt="The Claude tab answering a question about an attached PDF"
            width={1560}
            height={708}
            aspect="aspect-[1560/708]"
            className="lg:col-span-3"
          />
          <div className="grid gap-4 lg:col-span-2">
            <Screenshot
              file="drop-claude.webp"
              alt="Dropping a file on the Ask Claude tile"
              width={1560}
              height={528}
              aspect="aspect-[3/1]"
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
        <ul className="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {points.map((p) => (
            <li key={p.title} className="reveal rounded-2xl border border-white/[0.08] bg-white/[0.025] p-5">
              <p.icon className="size-5" style={{ color: claude }} />
              <h3 className="mt-4 font-semibold">{p.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{p.text}</p>
            </li>
          ))}
        </ul>
        <p className="reveal mt-6 text-center text-xs text-muted-foreground/80">
          Uses Claude Sonnet 5.5 by default, with Opus 5.5 and Haiku 5.5 a click away. Usage is billed by Anthropic to your
          API account; Notchy adds nothing.
        </p>
      </div>
    </section>
  );
}
