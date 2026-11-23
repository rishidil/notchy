import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

export function SectionHeading({
  eyebrow,
  title,
  description,
  className,
  align = "center",
}: {
  eyebrow: string;
  title: React.ReactNode;
  description?: React.ReactNode;
  className?: string;
  align?: "center" | "left";
}) {
  return (
    <div
      className={cn(
        "reveal flex flex-col gap-4",
        align === "center" ? "items-center text-center mx-auto max-w-2xl" : "items-start",
        className
      )}
    >
      <Badge
        variant="outline"
        className="h-6 rounded-full border-white/10 bg-white/[0.03] px-3 text-[0.72rem] font-medium uppercase tracking-[0.14em] text-muted-foreground"
      >
        {eyebrow}
      </Badge>
      <h2 className="text-balance text-3xl font-semibold tracking-tight sm:text-5xl">
        {title}
      </h2>
      {description ? (
        <p className="text-pretty text-base leading-relaxed text-muted-foreground sm:text-lg">
          {description}
        </p>
      ) : null}
    </div>
  );
}
