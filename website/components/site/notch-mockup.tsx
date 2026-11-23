import {
  CalendarDays,
  CloudSun,
  House,
  Pause,
  SkipBack,
  SkipForward,
  Timer,
  Video,
} from "lucide-react";

function Eq({ className = "" }: { className?: string }) {
  return (
    <div className={`nm-eq flex items-end gap-[3px] ${className}`} aria-hidden>
      <span />
      <span />
      <span />
      <span />
    </div>
  );
}

function AlbumArt({ className = "" }: { className?: string }) {
  return (
    <div
      className={`relative overflow-hidden bg-[conic-gradient(from_200deg_at_35%_40%,#ffa84d,#ff619e,#bf59ff,#5c6bff,#59d9ff,#ffa84d)] ${className}`}
    >
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_70%_75%,rgb(0_0_0/0.45),transparent_60%)]" />
    </div>
  );
}

/** Pure-CSS animation of the notch growing into a live activity, then a full island. */
export function NotchMockup() {
  return (
    <div className="nm-stage relative mx-auto w-full max-w-5xl" aria-hidden>
      {/* Screen */}
      <div className="relative aspect-[16/10] w-full overflow-hidden rounded-t-[22px] border border-b-0 border-white/10 bg-[#0a0912] sm:aspect-[16/7] sm:rounded-t-[34px]">
        {/* Wallpaper */}
        <div className="nm-aurora absolute -inset-[15%]">
          <div className="absolute left-[8%] top-[20%] h-[70%] w-[45%] rounded-full bg-[#5c6bff] opacity-50 blur-[90px]" />
          <div className="absolute right-[6%] top-[10%] h-[60%] w-[40%] rounded-full bg-[#bf59ff] opacity-45 blur-[90px]" />
          <div className="absolute bottom-[0%] left-[35%] h-[50%] w-[35%] rounded-full bg-[#ff619e] opacity-35 blur-[100px]" />
          <div className="absolute bottom-[10%] right-[18%] h-[35%] w-[25%] rounded-full bg-[#ffa84d] opacity-25 blur-[90px]" />
          <div className="absolute left-[0%] bottom-[5%] h-[35%] w-[25%] rounded-full bg-[#59d9ff] opacity-25 blur-[90px]" />
        </div>
        <div className="bg-grid absolute inset-0 opacity-40 [mask-image:linear-gradient(to_bottom,black,transparent_85%)]" />

        {/* Menu bar */}
        <div className="absolute inset-x-0 top-0 flex h-[var(--nh)] items-center justify-between bg-black/25 px-3 text-[10px] font-medium text-white/85 backdrop-blur-md sm:px-5 sm:text-[13px]">
          <div className="flex items-center gap-3 sm:gap-5">
            <span className="size-2.5 rounded-full bg-white/85 sm:size-3" />
            <span className="font-semibold">Finder</span>
            <span className="hidden text-white/70 sm:inline">File</span>
            <span className="hidden text-white/70 sm:inline">Edit</span>
            <span className="hidden text-white/70 md:inline">View</span>
            <span className="hidden text-white/70 md:inline">Go</span>
          </div>
          <div className="flex items-center gap-3 text-white/80 sm:gap-4">
            <span className="hidden sm:inline">100%</span>
            <span className="hidden md:inline">Mon 9:41</span>
            <span className="md:hidden">9:41</span>
          </div>
        </div>

        {/* The island */}
        <div className="nm-island absolute left-1/2 top-0 z-10 -translate-x-1/2 overflow-hidden bg-black">
          {/* Live activity (collapsed) */}
          <div className="nm-live absolute inset-x-0 top-0 flex h-[var(--nh)] items-center justify-between px-2 sm:px-3">
            <AlbumArt className="size-4 rounded-[4px] sm:size-6 sm:rounded-md" />
            <Eq className="h-3 sm:h-4" />
          </div>

          {/* Expanded island */}
          <div className="nm-expanded absolute inset-0 flex flex-col px-4 pb-4 pt-2 sm:px-7 sm:pb-6 sm:pt-2.5">
            <div className="flex h-[calc(var(--nh)-6px)] items-center justify-between text-white/50">
              <div className="flex items-center gap-2.5 sm:gap-3.5">
                <House className="size-3 text-white sm:size-3.5" />
                <CalendarDays className="size-3 sm:size-3.5" />
                <Timer className="size-3 sm:size-3.5" />
                <CloudSun className="hidden size-3.5 sm:block" />
              </div>
              <div className="flex items-center gap-1.5 text-[9px] sm:text-[11px]">
                <span className="tabular-nums">84%</span>
                <span className="relative h-2 w-4 rounded-[3px] border border-white/40 sm:h-2.5 sm:w-5">
                  <span className="absolute inset-[1.5px] right-[30%] rounded-[1px] bg-[#59d9ff]" />
                </span>
              </div>
            </div>

            <div className="mt-2 flex flex-1 items-stretch gap-3 sm:mt-3 sm:gap-5">
              {/* Now playing */}
              <div className="flex min-w-0 flex-1 items-center gap-3 sm:gap-4">
                <AlbumArt className="size-14 shrink-0 rounded-xl shadow-[0_8px_30px_-6px_rgb(255_97_158/0.6)] sm:size-[104px] sm:rounded-2xl" />
                <div className="flex min-w-0 flex-1 flex-col gap-1.5 sm:gap-2.5">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="truncate text-[11px] font-semibold text-white sm:text-[15px]">
                        Afterglow Avenue
                      </div>
                      <div className="truncate text-[10px] text-white/50 sm:text-[13px]">
                        Neon Harbor
                      </div>
                    </div>
                    <Eq className="mt-0.5 h-3 sm:h-4" />
                  </div>
                  <div className="flex items-center gap-2 text-[8px] tabular-nums text-white/40 sm:text-[10px]">
                    <span>1:24</span>
                    <div className="relative h-1 flex-1 overflow-hidden rounded-full bg-white/15">
                      <div className="nm-progress bg-brand absolute inset-y-0 left-0 rounded-full" />
                    </div>
                    <span>3:52</span>
                  </div>
                  <div className="flex items-center justify-center gap-4 text-white sm:gap-6">
                    <SkipBack className="size-3 fill-current sm:size-4" />
                    <Pause className="size-4 fill-current sm:size-5" />
                    <SkipForward className="size-3 fill-current sm:size-4" />
                  </div>
                </div>
              </div>

              {/* Side widgets */}
              <div className="hidden w-[38%] flex-col gap-2.5 sm:flex">
                <div className="flex flex-1 items-center gap-3 rounded-2xl bg-white/[0.06] px-3.5">
                  <div className="h-8 w-1 rounded-full bg-[#5c6bff]" />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-[12px] font-medium text-white">
                      Design review
                    </div>
                    <div className="text-[11px] text-white/50">in 12 min · 2:30 PM</div>
                  </div>
                  <span className="inline-flex items-center gap-1 rounded-full bg-[#5c6bff] px-2.5 py-1 text-[11px] font-semibold text-white">
                    <Video className="size-3" />
                    Join
                  </span>
                </div>
                <div className="flex flex-1 items-center justify-between rounded-2xl bg-white/[0.06] px-3.5">
                  <div className="flex items-center gap-2.5">
                    <CloudSun className="size-6 text-[#ffa84d]" />
                    <div>
                      <div className="text-[15px] font-semibold leading-none text-white">21°</div>
                      <div className="mt-1 text-[11px] text-white/50">Partly cloudy</div>
                    </div>
                  </div>
                  <div className="flex items-center gap-1.5 text-[11px] text-white/60">
                    <Timer className="size-3.5 text-[#59d9ff]" />
                    <span className="tabular-nums">24:13</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Fade the screen into the page */}
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-1/3 bg-gradient-to-b from-transparent to-[#060608]" />
      </div>
    </div>
  );
}
