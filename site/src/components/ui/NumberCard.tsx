// One key number: big champagne figure (counts up) with its label underneath.
import type { SourcedNumber } from "../../data/types";
import { CountUp } from "./CountUp";
import { GlassCard } from "./GlassCard";

interface Props {
  number: SourcedNumber;
  label?: string; // override the data label (hero uses shorter labels from site.json)
  size?: "lg" | "md";
}

export function NumberCard({ number, label, size = "md" }: Props) {
  return (
    <GlassCard className="flex h-full flex-col justify-between gap-3 p-5">
      <CountUp
        display={number.display}
        className={`glow font-serif leading-none text-accent ${
          size === "lg" ? "text-4xl sm:text-5xl" : "text-3xl sm:text-4xl"
        }`}
      />
      <p className="text-sm leading-snug text-muted">{label ?? number.label}</p>
    </GlassCard>
  );
}
