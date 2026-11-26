// One tooltip for every chart: anchored to a point inside the chart box,
// placed above it (below when there is no room), kept inside the box.
// Values lead and labels follow; series are keyed by a short line.
import type { CSSProperties } from "react";
export interface TipRow {
  label: string;
  value: string;
  key?: string; // Tailwind bg-* class for the line key
}

export interface TipState {
  x: number;
  y: number;
  title: string;
  rows: TipRow[];
  /** "side": beside the point (line charts, so the axis and labels stay visible).
   *  "corner": pinned to the bottom-right of the box (x, y = that corner).
   *  "static": in the page flow (a readout under the chart, never over it). */
  place?: "above" | "side" | "corner" | "static";
}

const WIDTH = 224;

export function ChartTooltip({ tip, width }: { tip: TipState | null; width: number }) {
  if (!tip) return null;
  const w = Math.min(WIDTH, width);
  if (tip.place === "static") return <Box tip={tip} inFlow />;
  if (tip.place === "corner") {
    return <Box tip={tip} style={{ left: Math.max(0, tip.x - w), top: tip.y, width: w, transform: "translateY(-100%)" }} />;
  }
  if (tip.place === "side") {
    const right = tip.x + 16 + w <= width;
    const left = right ? tip.x + 16 : Math.max(0, tip.x - 16 - w);
    return <Box tip={tip} style={{ left, top: Math.max(0, tip.y - 24), width: w }} />;
  }
  const left = Math.max(0, Math.min(tip.x - WIDTH / 2, width - WIDTH));
  const below = tip.y < 96;
  return (
    <Box
      tip={tip}
      style={{
        left,
        top: tip.y,
        width: w,
        transform: below ? "translateY(14px)" : "translateY(calc(-100% - 14px))",
      }}
    />
  );
}

function Box({ tip, style, inFlow = false }: { tip: TipState; style?: CSSProperties; inFlow?: boolean }) {
  return (
    <div
      role="tooltip"
      className={`glass pointer-events-none px-3.5 py-2.5 text-xs ${inFlow ? "w-full" : "absolute z-10"}`}
      style={style}
    >
      <p className="mb-1.5 text-ink">{tip.title}</p>
      <dl className="space-y-1">
        {tip.rows.map((r) => (
          <div key={r.label} className="flex items-baseline justify-between gap-3">
            <dt className="flex items-center gap-2 text-muted">
              {r.key && <span aria-hidden="true" className={`h-0.5 w-3 shrink-0 rounded-full ${r.key}`} />}
              {r.label}
            </dt>
            <dd className="font-mono font-medium whitespace-nowrap text-ink tabular-nums">{r.value}</dd>
          </div>
        ))}
      </dl>
    </div>
  );
}
