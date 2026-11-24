import type { Metadata } from "next";
import { Footer } from "@/components/site/footer";
import { Nav } from "@/components/site/nav";
import { SITE } from "@/lib/site";

export const metadata: Metadata = {
  title: "Developer docs — Notchy",
  description:
    "How Notchy works: the app's architecture, its AI engines (Apple on-device, Claude via T3 Code, Claude API), the T3 Code integration, every network connection, and how to build and test it.",
};

const repo = SITE.githubUrl;
const src = (file: string) => `${repo}/blob/main/Sources/NotchIsland/${file}`;

const toc = [
  { id: "overview", label: "Overview" },
  { id: "architecture", label: "Architecture" },
  { id: "ai", label: "AI engines" },
  { id: "t3", label: "T3 Code integration" },
  { id: "connections", label: "Connections" },
  { id: "storage", label: "What's stored where" },
  { id: "automation", label: "URL automation" },
  { id: "build", label: "Build, test & release" },
  { id: "contribute", label: "Extending Notchy" },
];

function H2({ id, children }: { id: string; children: React.ReactNode }) {
  return (
    <h2 id={id} className="scroll-mt-24 border-t border-white/[0.06] pt-10 text-2xl font-semibold tracking-tight first:border-0 first:pt-0">
      {children}
    </h2>
  );
}

function H3({ children }: { children: React.ReactNode }) {
  return <h3 className="mt-8 text-lg font-semibold">{children}</h3>;
}

function P({ children }: { children: React.ReactNode }) {
  return <p className="mt-4 leading-relaxed text-muted-foreground">{children}</p>;
}

function C({ children }: { children: React.ReactNode }) {
  return <code className="rounded bg-white/10 px-1.5 py-0.5 font-mono text-[0.85em] text-foreground">{children}</code>;
}

function Pre({ children }: { children: string }) {
  return (
    <pre className="mt-4 overflow-x-auto rounded-xl border border-white/[0.08] bg-black/40 p-4 font-mono text-[13px] leading-relaxed text-foreground/90">
      {children}
    </pre>
  );
}

function UL({ children }: { children: React.ReactNode }) {
  return <ul className="mt-4 list-disc space-y-2 pl-5 leading-relaxed text-muted-foreground marker:text-white/30">{children}</ul>;
}

function Table({ head, rows }: { head: string[]; rows: React.ReactNode[][] }) {
  return (
    <div className="mt-5 overflow-x-auto rounded-xl border border-white/[0.08]">
      <table className="w-full min-w-[640px] text-left text-sm">
        <thead className="bg-white/[0.04] text-foreground">
          <tr>{head.map((h) => <th key={h} className="px-4 py-2.5 font-semibold">{h}</th>)}</tr>
        </thead>
        <tbody className="divide-y divide-white/[0.06] text-muted-foreground">
          {rows.map((r, i) => (
            <tr key={i} className="align-top">{r.map((c, j) => <td key={j} className="px-4 py-2.5">{c}</td>)}</tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Src({ file }: { file: string }) {
  return (
    <a href={src(file)} target="_blank" rel="noreferrer" className="font-mono text-[0.85em] text-foreground underline-offset-4 hover:underline">
      {file}
    </a>
  );
}

function Flow({ steps }: { steps: string[] }) {
  return (
    <ol className="mt-5 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
      {steps.map((s, i) => (
        <li key={s} className="flex gap-3 rounded-xl border border-white/[0.08] bg-white/[0.025] p-3 text-sm text-muted-foreground">
          <span className="flex size-6 shrink-0 items-center justify-center rounded-full bg-white/[0.08] text-xs font-semibold text-foreground">{i + 1}</span>
          <span>{s}</span>
        </li>
      ))}
    </ol>
  );
}

export default function DocsPage() {
  return (
    <>
      <Nav />
      <main className="mx-auto w-full max-w-6xl flex-1 px-4 py-14 sm:px-6 sm:py-20">
        <div className="max-w-3xl">
          <p className="text-sm font-medium text-[#d97757]">Developer docs</p>
          <h1 className="mt-3 text-4xl font-semibold tracking-[-0.03em] sm:text-5xl">How Notchy works</h1>
          <p className="mt-5 text-lg leading-relaxed text-muted-foreground">
            A high-level tour for developers: how the app is put together, how the AI engines and the T3 Code
            integration work, and exactly what Notchy connects to. The source is{" "}
            <a href={repo} target="_blank" rel="noreferrer" className="text-foreground underline-offset-4 hover:underline">on GitHub</a>{" "}
            under the MIT license.
          </p>
        </div>

        <div className="mt-14 grid gap-12 lg:grid-cols-[200px_minmax(0,1fr)]">
          <nav className="hidden lg:block">
            <ul className="sticky top-24 space-y-1 text-sm">
              {toc.map((t) => (
                <li key={t.id}>
                  <a href={`#${t.id}`} className="block rounded-md px-2 py-1 text-muted-foreground transition-colors hover:bg-white/[0.04] hover:text-foreground">
                    {t.label}
                  </a>
                </li>
              ))}
            </ul>
          </nav>

          <article className="min-w-0 max-w-3xl space-y-0">
            <H2 id="overview">Overview</H2>
            <P>
              Notchy is a single native macOS app written in Swift with SwiftUI and AppKit, built with Swift Package Manager.
              It has no third-party dependencies. It runs as a background (menu-bar style) app with no Dock icon, draws a
              transparent panel over the notch, and grows that panel into live activities and an expanded island with tabs.
            </P>
            <UL>
              <li>Requires Apple silicon and macOS 14+. The on-device AI engine needs macOS 26 with Apple Intelligence.</li>
              <li>Each feature only starts the services it needs, and only asks for permissions when you turn it on.</li>
              <li>Background work is coalesced and pauses while the display sleeps; an efficiency mode halves it if CPU use climbs.</li>
            </UL>

            <H2 id="architecture">Architecture</H2>
            <P>Three layers, all on the main thread except for I/O, which runs on background queues and hops back:</P>
            <Table
              head={["Layer", "What it does", "Key files"]}
              rows={[
                ["Window", "A borderless, non-activating panel above the menu bar. Samples the pointer on a light timer (not every mouse event), passes clicks through outside the island, detects file drags.", <Src key="w" file="NotchWindowController.swift" />],
                ["View model", "One ObservableObject: expanded/collapsed state, which live activity wins, tabs, sizes, drop actions, URL commands. Merges every service's changes into one publisher.", <Src key="v" file="NotchViewModel.swift" />],
                ["Views", "The notch shape, collapsed live activities, the expanded tabs and Settings.", <span key="s"><Src file="NotchViews.swift" />, <Src file="ExpandedViews.swift" />, <Src file="FeatureTabs.swift" />, <Src file="AssistantTab.swift" />, <Src file="SettingsView.swift" /></span>],
                ["Services", "One class per feature (music, calendar, weather, timers, Bluetooth, agents, AI…), each an ObservableObject started and stopped by the view model.", <span key="x"><Src file="AssistantService.swift" />, <Src file="AgentsService.swift" />, <Src file="MusicController.swift" />, …</span>],
              ]}
            />
            <P>
              <strong className="text-foreground">Live activities</strong> are picked by priority in{" "}
              <C>NotchViewModel.activity</C>: short-lived pop-ups (HUD, notifications, toasts) first, then a running timer,
              an agent waiting for you, the AI working on an answer you aren&apos;t looking at, running agents, music, and an
              upcoming meeting.
            </P>

            <H2 id="ai">AI engines</H2>
            <P>
              The AI tab (<Src file="AssistantTab.swift" />) shows one conversation. <Src file="AssistantService.swift" /> owns
              it and hands each question to one of three engines behind a common <C>ChatEngine</C> protocol in{" "}
              <Src file="ChatEngines.swift" />. Each engine streams progress (text so far, what it&apos;s doing, sources,
              pending approvals) and returns an answer or an error.
            </P>
            <Table
              head={["Engine", "How it works", "Cost & privacy"]}
              rows={[
                [<strong key="a" className="text-foreground">On-device</strong>, <>Apple&apos;s Foundation Models framework (<C>LanguageModelSession</C>, streamed). Short text files are pasted into the prompt; the model&apos;s context is about 4,000 tokens. The session is pre-warmed when the tab opens.</>, "Free. Runs entirely on the Mac, works offline."],
                [<strong key="b" className="text-foreground">Claude via T3 Code</strong>, <>Each chat is a T3 Code thread in a dedicated &ldquo;Notchy&rdquo; project, run by the Claude Code that T3 Code hosts. Replies are read from T3 Code&apos;s local database while Claude works. Details below.</>, "Uses the user's own Claude plan. Notchy never sees Claude credentials."],
                [<strong key="c" className="text-foreground">Claude API</strong>, <>The Messages API over HTTPS with server-sent events: web search (<C>web_search_20260209</C>) with cited sources, attachments as image/document blocks, prompt caching, server-side refusal fallbacks, and resuming <C>pause_turn</C> after long searches.</>, "Pay per use on the user's Anthropic account (API key or ant CLI sign-in)."],
              ]}
            />

            <H3>Picking an engine</H3>
            <P>
              In <strong className="text-foreground">Automatic</strong> mode (<C>EngineRouter</C>), short questions without
              files go to the on-device model; files, long questions and &ldquo;Ask Claude instead&rdquo; go to Claude (T3 Code
              first, then the API). A chat keeps its engine for follow-ups. When a different engine joins mid-chat, it gets
              a short transcript of the conversation so far. Users can also pin one engine in Settings.
            </P>

            <H3>Claude via T3 Code, step by step</H3>
            <Flow
              steps={[
                "Notchy creates ~/Library/Application Support/Notchy/Chats and registers it once: t3 project add --title Notchy",
                "The first question starts a thread: t3 thread start --json --provider claudeAgent --model <model> <folder> -",
                "Follow-ups go to the same thread: t3 thread send <threadId> -",
                "Dropped files are copied into the chat's files/ folder so Claude can read them without asking.",
                "While the run works, Notchy reads its messages and turn items from T3 Code's SQLite database (read-only) a few times a second.",
                "If Claude needs an approval or asks a question, it appears in the chat and is answered through T3 Code's local API.",
              ]}
            />
            <P>
              The first message carries a short preamble telling Claude Code it&apos;s answering a chat, not doing a coding
              task. Availability comes from T3 Code&apos;s provider cache (<C>~/.t3/caches/claudeAgent.json</C>): installed,
              enabled and signed in. The chats project is hidden from Notchy&apos;s Agents tab but visible in T3 Code, which
              doubles as the chat history.
            </P>

            <H3>Why not &ldquo;Sign in with Claude&rdquo;?</H3>
            <P>
              Anthropic doesn&apos;t allow third-party apps to offer Claude.ai login or to use Free, Pro, Max or Ultra plan
              credentials on users&apos; behalf (see{" "}
              <a href="https://code.claude.com/docs/en/legal-and-compliance" target="_blank" rel="noreferrer" className="text-foreground underline-offset-4 hover:underline">
                Anthropic&apos;s legal and compliance page
              </a>
              ). So Notchy offers the two supported routes: the user&apos;s own Claude Code running inside T3 Code, and the
              API with the user&apos;s own key or Anthropic Console sign-in.
            </P>

            <H2 id="t3">T3 Code integration</H2>
            <P>
              The Agents tab (<Src file="AgentsService.swift" />) lists, prompts and starts T3 Code agents with T3 Code&apos;s
              own CLI, and reads status from its database so it can react instantly without polling the CLI.
            </P>
            <Table
              head={["Need", "How"]}
              rows={[
                ["Projects & threads", <><C>t3 thread list --json --project</C>, plus project folders from <C>projection_projects</C></>],
                ["Status (cheap, every few seconds)", <>The latest run&apos;s status and pending requests from <C>orchestration_v2_projection_runs</C> and <C>…_runtime_requests</C>, only when the database&apos;s files have changed</>],
                ["Messages", <><C>t3 thread show &lt;id&gt; --json --messages 6</C>, only when that thread&apos;s messages changed</>],
                ["Send / start", <><C>t3 thread send</C> and <C>t3 thread start</C>; a busy agent gets the message as its next turn</>],
                ["Approval & question details", <><C>approval_request</C> and <C>user_input_request</C> turn items for pending runtime requests</>],
                ["Answering them", "T3 Code's local server API (below), because the CLI can't respond to requests"],
              ]}
            />
            <H3>Answering approvals and questions</H3>
            <P>
              <Src file="T3Remote.swift" /> does what T3 Code&apos;s own remote clients do, entirely on the user&apos;s Mac:
            </P>
            <Flow
              steps={[
                "Ask the CLI for a scoped token once: t3 auth session issue --scope orchestration:read --scope orchestration:operate --label Notchy",
                "Keep it in the keychain. The user can revoke it in Settings (t3 auth session revoke).",
                "Read the server's address from ~/.t3/userdata/server-runtime.json (e.g. http://127.0.0.1:3773).",
                "Exchange the token for a one-time ticket: POST /api/auth/websocket-ticket/rpc",
                "Open ws://127.0.0.1:3773/ws?orchestrationProtocol=2&wsTicket=… and send one orchestration.dispatchCommand request.",
                "The command is runtime-request.respond with a decision (accept, acceptForSession, decline) or answers keyed by question id.",
              ]}
            />
            <Pre>{`{ "_tag": "Request", "id": "1", "tag": "orchestration.dispatchCommand", "headers": [],
  "payload": { "type": "runtime-request.respond", "commandId": "<uuid>",
               "threadId": "<thread>", "requestId": "<request>",
               "decision": "accept" } }          // or "answers": { "<question id>": "Label" }`}</Pre>
            <P>
              Single-choice answers are a string and multi-choice answers an array of labels. These are T3 Code internals,
              not a published API, so Notchy falls back gracefully (&ldquo;Review in T3&rdquo;) if a T3 Code update changes them.
            </P>

            <H2 id="connections">Connections</H2>
            <P>Everything Notchy talks to, and when. Nothing is contacted unless the feature that needs it is turned on.</P>
            <Table
              head={["Connection", "Used for", "What's sent"]}
              rows={[
                ["Apple Foundation Models (on-device)", "Quick AI answers", "Nothing leaves the Mac"],
                ["T3 Code CLI, database & local server (127.0.0.1)", "Agents tab, approvals, Claude chats", "Stays on the Mac; Claude Code inside T3 Code then talks to Anthropic on the user's plan"],
                ["api.anthropic.com", "Claude API engine", "The question, the chat so far and attached files, with the user's key"],
                ["api.open-meteo.com (and its geocoding API)", "Weather", "Your location's coordinates, or the city name you search for in Settings"],
                ["lrclib.net", "Lyrics", "Song title, artist and duration"],
                ["api.github.com / github.com", "Update checks (daily) and downloads", "Nothing personal; the app's version in the User-Agent"],
                ["Spotify, Music, System Events, Amphetamine (AppleScript)", "Media controls, Dark Mode, Keep Awake", "Local Apple Events"],
                ["EventKit, CoreAudio, IOKit, IOBluetooth, DisplayServices", "Calendar, volume, battery, Bluetooth, brightness", "Local system frameworks"],
                ["Notification Center's database (read-only)", "Notification previews & history", "Local; needs Full Disk Access"],
              ]}
            />

            <H2 id="storage">What&apos;s stored where</H2>
            <Table
              head={["Item", "Where"]}
              rows={[
                ["Claude API key", <>Keychain, service <C>dev.notchisland.app</C>, account <C>claude-api-key</C></>],
                ["T3 Code access token", <>Keychain, account <C>t3-session</C> (revocable)</>],
                ["Settings, tabs, AI engine choice, models", "UserDefaults (dev.notchisland.app)"],
                ["Claude chats via T3 Code", "Threads in T3 Code's \"Notchy\" project; attachments under ~/Library/Application Support/Notchy/Chats/files"],
                ["On-device and API chats", "In memory only, cleared on New Chat or quit"],
                ["To-dos and the file shelf (file paths only)", "UserDefaults on the Mac"],
                ["Screen Time tallies", "~/Library/Application Support (on the Mac only)"],
              ]}
            />

            <H2 id="automation">URL automation</H2>
            <P>Handy from Shortcuts, Raycast or a terminal:</P>
            <Pre>{`open "notchy://ask?q=What%27s%20a%20good%20name%20for%20a%20cat"   # ask the AI tab
open "notchy://open?tab=claude"     # open a tab (home, claude, calendar, timer, weather, agents, shelf, …)
open "notchy://timer?minutes=10"
open "notchy://pomodoro"
open "notchy://settings?page=connections"`}</Pre>

            <H2 id="build">Build, test &amp; release</H2>
            <Pre>{`git clone ${repo}.git && cd notchy
./build.sh            # build build/Notchy.app
./build.sh install    # build, copy to /Applications, launch
./scripts/test.sh     # unit tests (offline, a few seconds)`}</Pre>
            <P>
              The test suite (Swift Testing) covers the Claude request builder and stream parser (text, thinking, web search,
              citations, paused turns, refusals, fallbacks), attachments, engine routing, the on-device prompt, the whole
              API conversation against a mocked server, and the T3 Code chat engine end to end against a fake <C>t3</C>{" "}
              command and a scratch copy of T3 Code&apos;s database. Live tests against real services are opt-in:
            </P>
            <Pre>{`NOTCHY_LIVE_ONDEVICE=1 ./scripts/test.sh --filter Live     # Apple's model on this Mac
NOTCHY_LIVE_T3_CHAT=1 ./scripts/test.sh --filter Live      # a real chat through T3 Code (your Claude plan)
NOTCHY_LIVE_T3=1 ./scripts/test.sh --filter Live           # round trip to T3 Code's local API
NOTCHY_LIVE_CLAUDE=1 ANTHROPIC_API_KEY=sk-ant-… ./scripts/test.sh --filter Live   # Claude API (a few cents)`}</Pre>
            <P>
              <C>--demo</C> launches with sample data and never saves anything; <C>--demo --snapshots &lt;folder&gt;</C>{" "}
              renders the website&apos;s screenshots. Releases are DMG and ZIP files on GitHub Releases; the in-app updater
              downloads the ZIP and only installs it if it&apos;s signed with the same certificate as the running app.
            </P>

            <H2 id="contribute">Extending Notchy</H2>
            <UL>
              <li>
                <strong className="text-foreground">A new tab:</strong> add a case to <C>NotchTab</C> in{" "}
                <Src file="Features.swift" />, a service if it needs one (start/stop it in{" "}
                <C>applyFeatureState</C>), and a view in the tab switch in <Src file="ExpandedViews.swift" />.
              </li>
              <li>
                <strong className="text-foreground">A new AI engine</strong> (Ollama, another provider…): implement{" "}
                <C>ChatEngine</C> (<C>ask</C> streams <C>EngineUpdate</C>s and returns an <C>EngineResult</C>; <C>reset</C>{" "}
                forgets the chat), add a <C>ChatEngineKind</C>, report availability in{" "}
                <C>AssistantService.refreshAvailability</C>, and decide where <C>EngineRouter</C> should send questions.
              </li>
              <li>
                <strong className="text-foreground">A new drop action:</strong> add a case to <C>DropAction</C> and handle it in{" "}
                <C>NotchViewModel.run(_:on:)</C>.
              </li>
            </UL>
            <P>
              Issues and pull requests are welcome on{" "}
              <a href={repo} target="_blank" rel="noreferrer" className="text-foreground underline-offset-4 hover:underline">GitHub</a>.
              When reporting a bug, right-click the island → <strong className="text-foreground">Copy Diagnostics</strong>{" "}
              for an anonymous report.
            </P>
          </article>
        </div>
      </main>
      <Footer />
    </>
  );
}
