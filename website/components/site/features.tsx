"use client";

import { useRef, useState } from "react";
import { BatteryCharging, Check, Gauge, ShieldCheck } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Screenshot } from "@/components/site/screenshot";
import { SectionHeading } from "@/components/site/section-heading";
import { FEATURES } from "@/lib/features";
import { cn } from "@/lib/utils";

const EXTRAS = [
  {
    name: "Battery & charging",
    text: "A charging animation when you plug in, battery level in the header.",
    icon: BatteryCharging,
    color: "#59d9ff",
  },
  {
    name: "~0% CPU at idle",
    text: "Native SwiftUI + AppKit with zero dependencies.",
    icon: Gauge,
    color: "#ffa84d",
  },
  {
    name: "Private by design",
    text: "Everything runs on your Mac. No accounts, no tracking.",
    icon: ShieldCheck,
    color: "#5c6bff",
  },
];

export function Features() {
  const [active, setActive] = useState(FEATURES[0].id);
  const showcaseRef = useRef<HTMLDivElement>(null);

  function select(id: string) {
    setActive(id);
    showcaseRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  return (
    <section id="features" className="relative py-20 sm:py-28">
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <SectionHeading
          eyebrow="Features"
          title={
            <>
              One notch. <span className="text-brand">Fourteen superpowers.</span>
            </>
          }
          description="Hover the notch to expand it. When something's happening, it grows a live activity — then gets out of your way."
        />

        <div ref={showcaseRef} className="reveal mt-14 scroll-mt-24 sm:mt-16">
          <Tabs value={active} onValueChange={setActive} className="gap-8">
            <TabsList
              aria-label="Features"
              className="mx-auto flex w-full max-w-full flex-wrap justify-center gap-1.5 rounded-none bg-transparent p-0 group-data-horizontal/tabs:h-auto"
            >
              {FEATURES.map((f) => (
                <TabsTrigger
                  key={f.id}
                  value={f.id}
                  className="h-8 flex-none rounded-full border-white/[0.08] bg-white/[0.02] px-2.5 text-[12px] sm:h-9 sm:px-3.5 sm:text-[13px] data-active:border-white/20 data-active:bg-white/[0.09] dark:data-active:border-white/20 dark:data-active:bg-white/[0.09]"
                >
                  <f.icon style={{ color: f.color }} />
                  {f.name}
                </TabsTrigger>
              ))}
            </TabsList>

            {FEATURES.map((f) => (
              <TabsContent
                key={f.id}
                value={f.id}
                className="animate-in fade-in-0 slide-in-from-bottom-2 duration-500"
              >
                <div className="relative">
                  <div
                    className="pointer-events-none absolute inset-x-0 -inset-y-12 -z-10 opacity-40 blur-3xl sm:-inset-x-10"
                    style={{
                      background: `radial-gradient(50% 50% at 50% 50%, ${f.color}55, transparent 70%)`,
                    }}
                  />
                  <Screenshot
                    file={f.screenshot}
                    alt={`${f.name} — Notchy screenshot`}
                    width={1520}
                    height={520}
                    eager={f.id === FEATURES[0].id}
                  />
                </div>

                <div className="mt-8 grid gap-6 md:mt-10 md:grid-cols-2 md:gap-12">
                  <div>
                    <div className="flex items-center gap-3">
                      <span
                        className="grid size-9 place-items-center rounded-xl border border-white/10"
                        style={{ background: `${f.color}1f`, color: f.color }}
                      >
                        <f.icon className="size-[18px]" />
                      </span>
                      <span className="text-sm font-medium text-muted-foreground">{f.name}</span>
                    </div>
                    <h3 className="mt-4 text-balance text-2xl font-semibold tracking-tight sm:text-3xl">
                      {f.tagline}
                    </h3>
                    <p className="mt-3 text-pretty text-base leading-relaxed text-muted-foreground">
                      {f.description}
                    </p>
                  </div>
                  <ul className="flex flex-col justify-center gap-3 text-[15px]">
                    {f.points.map((p) => (
                      <li key={p} className="flex items-start gap-3">
                        <span
                          className="mt-0.5 grid size-5 shrink-0 place-items-center rounded-full"
                          style={{ background: `${f.color}26`, color: f.color }}
                        >
                          <Check className="size-3" strokeWidth={3} />
                        </span>
                        <span className="text-foreground/90">{p}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              </TabsContent>
            ))}
          </Tabs>
        </div>

        <div className="mt-20 grid grid-cols-2 gap-2.5 sm:gap-3 lg:grid-cols-4">
          {FEATURES.map((f) => (
            <button
              key={f.id}
              type="button"
              onClick={() => select(f.id)}
              className="reveal group rounded-xl text-left outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
            >
              <Card
                size="sm"
                className={cn(
                  "h-full bg-white/[0.025] ring-white/[0.07] transition-all duration-300 group-hover:-translate-y-0.5 group-hover:bg-white/[0.05] group-hover:ring-white/15",
                  active === f.id && "bg-white/[0.06] ring-white/20"
                )}
              >
                <CardContent className="flex items-start gap-3">
                  <span
                    className="grid size-8 shrink-0 place-items-center rounded-lg"
                    style={{ background: `${f.color}1f`, color: f.color }}
                  >
                    <f.icon className="size-4" />
                  </span>
                  <div className="min-w-0">
                    <div className="text-[13px] font-medium sm:text-sm">{f.name}</div>
                    <div className="mt-0.5 hidden text-[13px] leading-snug text-muted-foreground sm:block">
                      {f.tagline}
                    </div>
                  </div>
                </CardContent>
              </Card>
            </button>
          ))}
          {EXTRAS.map((e) => (
            <Card
              key={e.name}
              size="sm"
              className="reveal bg-transparent ring-white/[0.07] [background-image:linear-gradient(135deg,rgb(255_255_255/0.035),transparent)]"
            >
              <CardContent className="flex items-start gap-3">
                <span
                  className="grid size-8 shrink-0 place-items-center rounded-lg"
                  style={{ background: `${e.color}1f`, color: e.color }}
                >
                  <e.icon className="size-4" />
                </span>
                <div className="min-w-0">
                  <div className="text-[13px] font-medium sm:text-sm">{e.name}</div>
                  <div className="mt-0.5 hidden text-[13px] leading-snug text-muted-foreground sm:block">
                    {e.text}
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
}
