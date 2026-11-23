import { KeyRound, ListOrdered, ToggleRight } from "lucide-react";
import { Screenshot } from "@/components/site/screenshot";
import { SectionHeading } from "@/components/site/section-heading";

const items = [
  {
    icon: ListOrdered,
    title: "Pick your tabs — and their order",
    text: "Choose exactly which tabs your notch shows, from Home and Calendar to Weather and Screen Time, and put them in the order you like.",
    color: "#59d9ff",
  },
  {
    icon: ToggleRight,
    title: "Toggle every feature",
    text: "Live activities, notification previews, the volume & brightness HUD, Launch at Login and more. Turn on only what you want.",
    color: "#bf59ff",
  },
  {
    icon: KeyRound,
    title: "Grant permissions in one place",
    text: "Calendar, Location, Bluetooth, Automation, Full Disk Access, Accessibility: each one is only requested when a tab you turned on needs it, and you can grant it right from Settings.",
    color: "#ffa84d",
  },
];

export function Customize() {
  return (
    <section id="customize" className="relative py-20 sm:py-28">
      <div className="pointer-events-none absolute inset-x-0 top-1/3 -z-10 h-[500px] bg-[radial-gradient(50%_50%_at_70%_50%,rgb(191_89_255/0.12),transparent)]" />
      <div className="mx-auto grid max-w-6xl items-center gap-14 px-4 sm:px-6 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)] lg:gap-16">
        <div>
          <SectionHeading
            align="left"
            eyebrow="Make it yours"
            title={
              <>
                Set up in a minute. <span className="text-brand">Tuned for years.</span>
              </>
            }
            description="The Settings window opens on first launch, so your island is exactly how you want it from day one. Reopen it anytime from the ⚙︎ in the island."
          />
          <ul className="mt-10 flex flex-col gap-6">
            {items.map((it) => (
              <li key={it.title} className="reveal flex gap-4">
                <span
                  className="grid size-10 shrink-0 place-items-center rounded-xl border border-white/10"
                  style={{ background: `${it.color}1a`, color: it.color }}
                >
                  <it.icon className="size-5" />
                </span>
                <div>
                  <h3 className="font-medium">{it.title}</h3>
                  <p className="mt-1 text-[15px] leading-relaxed text-muted-foreground">{it.text}</p>
                </div>
              </li>
            ))}
          </ul>
        </div>

        <div className="reveal relative">
          <div className="pointer-events-none absolute -inset-8 -z-10 rounded-[3rem] bg-[conic-gradient(from_180deg_at_50%_50%,rgb(89_217_255/0.18),rgb(92_107_255/0.18),rgb(191_89_255/0.18),rgb(255_97_158/0.18),rgb(255_168_77/0.18),rgb(89_217_255/0.18))] blur-3xl" />
          <Screenshot
            file="settings.webp"
            alt="Notchy Settings window"
            width={1400}
            height={1000}
            aspect="aspect-[223/181]"
          />
        </div>
      </div>
    </section>
  );
}
