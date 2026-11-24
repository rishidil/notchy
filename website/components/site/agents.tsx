import { Bell, Download, Hand, ToggleRight } from "lucide-react";
import { Screenshot } from "@/components/site/screenshot";
import { SectionHeading } from "@/components/site/section-heading";

const steps = [
  {
    icon: Download,
    title: "Install T3 Code and open it once",
    text: (
      <>
        Get the desktop app from{" "}
        <a href="https://t3.codes" target="_blank" rel="noreferrer" className="text-foreground underline-offset-4 hover:underline">
          t3.codes
        </a>{" "}
        and add your projects. Opening it once installs the <code className="rounded bg-white/10 px-1 py-0.5 text-[0.85em]">t3</code> command
        Notchy talks to.
      </>
    ),
  },
  {
    icon: ToggleRight,
    title: "Turn on the Agents tab",
    text: (
      <>
        In Notchy, open <span className="text-foreground">⚙︎ → Settings → Tabs</span> and switch on{" "}
        <span className="text-foreground">Agents (T3 Code)</span>. Your projects show up automatically; check them under{" "}
        <span className="text-foreground">Settings → Connections</span>.
      </>
    ),
  },
  {
    icon: Hand,
    title: "Approve and answer from the notch",
    text: "When an agent wants to run a command or change files, approve or decline it right there. When it asks a question, tap an answer or type your own, and it carries on.",
  },
  {
    icon: Bell,
    title: "Get a live activity while they work",
    text: "The notch shows what's running and for how long, pings you when an agent finishes, and turns orange the moment one needs you. Click to jump straight to it.",
  },
];

export function Agents() {
  return (
    <section id="agents" className="relative py-20 sm:py-28">
      <div className="pointer-events-none absolute inset-x-0 top-1/4 -z-10 h-[500px] bg-[radial-gradient(50%_50%_at_30%_50%,rgb(92_107_255/0.14),transparent)]" />
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <SectionHeading
          eyebrow="Agents"
          title={
            <>
              Your AI agents, <span className="text-brand">one glance away.</span>
            </>
          }
          description="Connect T3 Code to see, prompt and start your coding agents, and approve their actions or answer their questions without leaving what you're doing. Everything stays on your Mac."
        />
        <div className="reveal mt-12 grid gap-4 lg:grid-cols-2">
          <Screenshot file="approval.webp" alt="Approving an agent's command from the notch" width={1560} height={528} aspect="aspect-[3/1]" />
          <Screenshot file="agents-live.webp" alt="A live activity showing an agent at work" width={1560} height={520} aspect="aspect-[3/1]" />
        </div>
        <ol className="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {steps.map((s, i) => (
            <li key={s.title} className="reveal rounded-2xl border border-white/[0.08] bg-white/[0.025] p-5">
              <div className="flex items-center gap-3">
                <span className="flex size-8 items-center justify-center rounded-full bg-white/[0.06] text-sm font-semibold text-muted-foreground">
                  {i + 1}
                </span>
                <s.icon className="size-5 text-[#bf59ff]" />
              </div>
              <h3 className="mt-4 font-semibold">{s.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{s.text}</p>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}
