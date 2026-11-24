import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { SectionHeading } from "@/components/site/section-heading";
import { SITE } from "@/lib/site";

const faqs: { q: string; a: React.ReactNode }[] = [
  {
    q: "Is it really free?",
    a: (
      <p>
        Yes. Notchy is free and open source under the MIT license. No account, no
        subscription, no ads. The full source is on{" "}
        <a href={SITE.githubUrl} target="_blank" rel="noreferrer">
          GitHub
        </a>
        .
      </p>
    ),
  },
  {
    q: "Is my data private?",
    a: (
      <p>
        Everything runs on your Mac. Weather comes from Open-Meteo and lyrics from LRCLIB, and
        neither needs an account. Notification content and Screen Time data never leave your Mac. With
        Claude, only what you type in the Claude tab and the files you drop on Ask Claude are sent to
        Anthropic, using your own account.
      </p>
    ),
  },
  {
    q: "Why does macOS show a security warning?",
    a: (
      <p>
        The app isn&rsquo;t notarized through Apple&rsquo;s paid developer program, so macOS
        can&rsquo;t verify who made it. The code is open for anyone to inspect, and you only need to
        click <b>Open Anyway</b> in System Settings → Privacy &amp; Security once.
      </p>
    ),
  },
  {
    q: "Does it work on Macs without a notch?",
    a: (
      <p>
        Yes — on an M1 MacBook Air, 13&Prime; MacBook Pro, iMac or external display, the island stays
        hidden until something happens (music, a timer, volume…), then appears as a slim pill at the
        top of the screen. Push your cursor to the top center to open it. Prefer something to click? Turn
        on <strong>Always show a small Notchy logo</strong> in Settings → Features for a tiny logo at the
        top of the screen.
      </p>
    ),
  },
  {
    q: "Which music apps are supported?",
    a: (
      <p>
        Spotify and Apple Music, including artwork, playback controls, seeking and live lyrics.
      </p>
    ),
  },
  {
    q: "How do I connect T3 Code?",
    a: (
      <p>
        Install the T3 Code desktop app and open it once, then turn on <strong>Agents (T3 Code)</strong> in
        Notchy&apos;s Settings → Tabs. Your projects appear automatically. If one is missing, add its folder in
        Settings → Connections. When an agent needs an approval or has a question, you can answer it right in the
        notch. Notchy gets its own access token from T3 Code for that, kept in your keychain and revocable in
        Settings → Connections.
      </p>
    ),
  },
  {
    q: "What do I need to use Claude?",
    a: (
      <p>
        An Anthropic API key, which you can create at{" "}
        <a href="https://platform.claude.com/settings/keys" target="_blank" rel="noreferrer">
          platform.claude.com
        </a>
        . Paste it once in Settings → Connections → Claude. You pay Anthropic directly for what you use (a quick question
        with the default Sonnet 5.5 costs around a cent or less; each web search adds $0.01); Notchy itself stays free. Claude.ai
        Pro and Max subscriptions can&apos;t be used by other apps.
      </p>
    ),
  },
  {
    q: "How do updates work?",
    a: (
      <p>
        From version 1.3, Notchy checks for new versions once a day and shows a pop-up in the notch when one is
        ready. Click it and Notchy updates itself in a few seconds, keeping your settings and permissions. It only
        installs updates signed by the same developer certificate. You can also check in Settings → About.
      </p>
    ),
  },
  {
    q: "How do I quit or change settings?",
    a: (
      <p>
        Right-click the island, or click the ⚙︎ in the expanded view and choose{" "}
        <b>Settings</b>. Turn on <b>Launch at Login</b> there so it starts with your Mac.
      </p>
    ),
  },
];

export function Faq() {
  return (
    <section id="faq" className="relative py-20 sm:py-28">
      <div className="mx-auto max-w-3xl px-4 sm:px-6">
        <SectionHeading eyebrow="FAQ" title="Questions, answered." />
        <Accordion
          type="single"
          collapsible
          defaultValue="item-0"
          className="reveal mt-12 rounded-2xl border border-white/[0.08] bg-white/[0.02] px-5 sm:px-7"
        >
          {faqs.map((f, i) => (
            <AccordionItem key={f.q} value={`item-${i}`} className="border-white/[0.07]">
              <AccordionTrigger className="py-5 text-base font-medium hover:no-underline">
                {f.q}
              </AccordionTrigger>
              <AccordionContent className="pb-5 text-[15px] leading-relaxed text-muted-foreground [&_b]:font-medium [&_b]:text-foreground">
                {f.a}
              </AccordionContent>
            </AccordionItem>
          ))}
        </Accordion>
      </div>
    </section>
  );
}
