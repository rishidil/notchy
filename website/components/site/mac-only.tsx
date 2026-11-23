"use client";

import { useState } from "react";
import { Check, Laptop, Share } from "lucide-react";
import { Button } from "@/components/ui/button";
import { SITE } from "@/lib/site";
import { cn } from "@/lib/utils";

/**
 * Shown instead of the download button on phones and tablets (touch-first devices),
 * where the Mac installer is no use. Lets people send the link to their Mac.
 */
export function MacOnlyNotice({ className }: { className?: string }) {
  const [copied, setCopied] = useState(false);

  async function send() {
    const url = SITE.url;
    try {
      if (navigator.share) {
        await navigator.share({ title: "Notchy for Mac", url });
        return;
      }
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      // Share sheet dismissed or clipboard unavailable: nothing to do.
    }
  }

  return (
    <div
      className={cn(
        "w-full max-w-md flex-col items-center gap-3 rounded-2xl border border-white/10 bg-white/[0.04] p-5 text-center",
        className
      )}
    >
      <div className="flex items-center gap-2 font-semibold">
        <Laptop className="size-5 text-[#59d9ff]" />
        Notchy is a Mac app
      </div>
      <p className="text-sm leading-relaxed text-muted-foreground">
        Open this page on your Mac to download it. Requires <span className="text-foreground">macOS 14 Sonoma or later</span> on
        a Mac with <span className="text-foreground">Apple silicon (M1 or newer)</span>.
      </p>
      <Button type="button" onClick={send} className="h-11 w-full rounded-full text-base font-semibold">
        {copied ? <Check className="size-5" /> : <Share className="size-5" />}
        {copied ? "Link copied" : "Send link to my Mac"}
      </Button>
    </div>
  );
}
