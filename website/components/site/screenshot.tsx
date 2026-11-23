import Image from "next/image";
import { asset } from "@/lib/site";
import { cn } from "@/lib/utils";

/**
 * Renders a PNG from /public/screenshots inside a rounded frame.
 * `object-contain` keeps the real aspect ratio whatever the frame shape.
 */
export function Screenshot({
  file,
  alt,
  width,
  height,
  className,
  eager,
  aspect = "aspect-[38/13]",
}: {
  file: string;
  alt: string;
  width: number;
  height: number;
  className?: string;
  eager?: boolean;
  aspect?: string;
}) {
  return (
    <div
      className={cn(
        "relative overflow-hidden rounded-2xl border border-white/10 bg-[#0b0b10] shadow-[0_30px_80px_-30px_rgb(0_0_0/0.9)] ring-1 ring-black/40 sm:rounded-3xl",
        aspect,
        className
      )}
    >
      <Image
        src={asset(`/screenshots/${file}`)}
        alt={alt}
        width={width}
        height={height}
        loading={eager ? "eager" : "lazy"}
        className="absolute inset-0 h-full w-full object-contain"
      />
      <div className="pointer-events-none absolute inset-0 rounded-[inherit] ring-1 ring-inset ring-white/5" />
    </div>
  );
}
