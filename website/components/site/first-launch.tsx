import { ShieldAlert, ShieldCheck, Terminal } from "lucide-react";
import { CopyButton } from "@/components/site/copy-button";
import { asset } from "@/lib/site";

const QUARANTINE_CMD = "xattr -dr com.apple.quarantine /Applications/Notchy.app && open /Applications/Notchy.app";

const steps = [
  {
    title: "Double-click Notchy in Applications",
    body: (
      <>
        macOS shows <span className="text-foreground">&ldquo;Notchy&rdquo; Not Opened</span>. Click{" "}
        <b className="font-medium text-foreground">Done</b>, not <i>Move to Trash</i>.
      </>
    ),
  },
  {
    title: "Open System Settings → Privacy & Security",
    body: <>Apple menu → System Settings, then Privacy &amp; Security in the sidebar.</>,
  },
  {
    title: "Click Open Anyway",
    body: (
      <>
        Scroll down to <span className="text-foreground">&ldquo;Notchy&rdquo; was blocked to protect your Mac</span> and click{" "}
        <b className="font-medium text-foreground">Open Anyway</b>.
      </>
    ),
  },
  {
    title: "Confirm",
    body: (
      <>
        Enter your Mac password or use Touch ID, then click <b className="font-medium text-foreground">Open Anyway</b> once more.
        Done. You won&rsquo;t see this again, and updates install themselves.
      </>
    ),
  },
];

/** Simplified illustration of the macOS "Not Opened" dialog. */
function DialogMock() {
  return (
    <div className="mx-auto w-full max-w-[280px] rounded-2xl border border-white/10 bg-[#1e1e22] p-4 text-center shadow-[0_20px_50px_-20px_rgb(0_0_0/0.9)]">
      <img src={asset("/icon-96.png")} alt="" className="mx-auto size-12" />
      <p className="mt-2 text-[13px] font-semibold">&ldquo;Notchy&rdquo; Not Opened</p>
      <p className="mt-1 text-[11px] leading-snug text-muted-foreground">
        Apple could not verify &ldquo;Notchy&rdquo; is free of malware that may harm your Mac or compromise your privacy.
      </p>
      <div className="mt-3 grid gap-1.5">
        <span className="rounded-md bg-[#0a84ff] py-1 text-[12px] font-medium text-white ring-2 ring-[#59d9ff]/70 ring-offset-2 ring-offset-[#1e1e22]">
          Done
        </span>
        <span className="rounded-md bg-white/10 py-1 text-[12px] text-white/80">Move to Trash</span>
      </div>
    </div>
  );
}

/** Simplified illustration of the Privacy & Security row with Open Anyway. */
function SettingsMock() {
  return (
    <div className="mx-auto w-full max-w-[340px] rounded-2xl border border-white/10 bg-[#1e1e22] p-4 shadow-[0_20px_50px_-20px_rgb(0_0_0/0.9)]">
      <p className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">Security</p>
      <div className="mt-2 flex items-center gap-3 rounded-lg bg-white/[0.05] p-3">
        <ShieldAlert className="size-5 shrink-0 text-amber-400" />
        <p className="flex-1 text-[11.5px] leading-snug">&ldquo;Notchy&rdquo; was blocked to protect your Mac.</p>
        <span className="shrink-0 rounded-md bg-white/15 px-2.5 py-1 text-[11.5px] font-medium ring-2 ring-[#59d9ff]/70 ring-offset-2 ring-offset-[#26262b]">
          Open Anyway
        </span>
      </div>
    </div>
  );
}

export function FirstLaunch() {
  return (
    <div id="first-launch" className="reveal mt-12 scroll-mt-24 overflow-hidden rounded-3xl border border-white/[0.08] bg-white/[0.02]">
      <div className="grid gap-8 p-5 sm:p-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,0.9fr)] lg:gap-12">
        <div className="min-w-0">
          <div className="flex items-center gap-2 text-sm font-medium text-[#59d9ff]">
            <ShieldCheck className="size-4" /> Opening Notchy for the first time
          </div>
          <h3 className="mt-3 text-2xl font-semibold tracking-tight sm:text-3xl">Getting past the &ldquo;could not verify&rdquo; warning</h3>
          <p className="mt-3 text-[15px] leading-relaxed text-muted-foreground">
            Notchy isn&rsquo;t sold through Apple&rsquo;s paid developer program yet, so macOS asks you to confirm the first time
            you open it. Nothing is wrong with the app, and its code is{" "}
            <a href="https://github.com/rishidil/notchy" target="_blank" rel="noreferrer" className="text-foreground underline-offset-4 hover:underline">
              open for anyone to inspect
            </a>
            . It takes about 20 seconds:
          </p>
          <ol className="mt-6 grid gap-4">
            {steps.map((s, i) => (
              <li key={s.title} className="flex gap-3">
                <span className="mt-0.5 grid size-7 shrink-0 place-items-center rounded-full bg-white/[0.07] text-[13px] font-semibold">
                  {i + 1}
                </span>
                <div className="min-w-0">
                  <p className="font-medium">{s.title}</p>
                  <p className="mt-0.5 text-[14px] leading-relaxed text-muted-foreground">{s.body}</p>
                </div>
              </li>
            ))}
          </ol>
          <p className="mt-5 text-[13px] leading-relaxed text-muted-foreground">
            On macOS 14 Sonoma you can also right-click Notchy in Applications, choose <b className="font-medium text-foreground">Open</b>,
            then <b className="font-medium text-foreground">Open</b> again.
          </p>
        </div>

        <div className="flex min-w-0 flex-col justify-center gap-5">
          <DialogMock />
          <div className="text-center text-xs text-muted-foreground">then, in System Settings → Privacy &amp; Security</div>
          <SettingsMock />
        </div>
      </div>

      <div className="border-t border-white/[0.06] bg-black/20 p-5 sm:px-8">
        <div className="flex items-center gap-2 text-sm font-medium">
          <Terminal className="size-4 text-muted-foreground" /> Prefer Terminal?
        </div>
        <p className="mt-1 text-[13px] text-muted-foreground">After dragging Notchy to Applications, this clears the warning and opens it:</p>
        <div className="mt-3 flex items-center gap-2 rounded-xl border border-white/[0.08] bg-black/40 py-2 pl-4 pr-2">
          <code className="min-w-0 flex-1 overflow-x-auto whitespace-nowrap font-mono text-[12.5px] text-foreground/90 [scrollbar-width:none]">
            {QUARANTINE_CMD}
          </code>
          <CopyButton text={QUARANTINE_CMD} />
        </div>
      </div>
    </div>
  );
}
