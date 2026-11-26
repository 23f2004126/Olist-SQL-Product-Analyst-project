// Shared helpers for the charts: data lookup, number formats, bar shapes,
// container width and the draw-in trigger. No numbers are defined here;
// everything a chart shows comes from site/data.
import { useInView, useReducedMotion } from "framer-motion";
import { useRef } from "react";
export { useWidth } from "../../../hooks/useWidth";
import { charts } from "../../../data/charts";
import type { Chart } from "../../../data/types";

export type Row = Chart["rows"][number];

/** Rows of a finding's chart in charts.json, by its id there. */
export function rowsOf(findingId: string, dataId: string | null): Row[] {
  return charts.data[findingId]?.find((c) => c.id === dataId)?.rows ?? [];
}

/** Rows a chart draws: the chart copy's `data` names them. */
export function chartRows(chartId: string): Row[] {
  const copy = charts.items[chartId];
  return rowsOf(copy.finding, copy.data);
}

export const num = (v: Row[string]) => (typeof v === "number" ? v : NaN);

// ---------------------------------------------------------------- formats
const formatters = new Map<string, Intl.NumberFormat>();
function nf(min: number, max: number, compact = false) {
  const key = `${min}-${max}-${compact}`;
  let f = formatters.get(key);
  if (!f) {
    f = new Intl.NumberFormat("en-US", {
      minimumFractionDigits: min,
      maximumFractionDigits: max,
      ...(compact ? { notation: "compact" as const } : {}),
    });
    formatters.set(key, f);
  }
  return f;
}
/** 93104 -> "93,104" */
export const fmtInt = (v: number) => nf(0, 0).format(v);
/** Two decimals, as the query output stores them: 7.1 -> "7.10" */
export const fmt2 = (v: number) => nf(2, 2).format(v);
export const fmtPct = (v: number) => `${fmt2(v)}%`;
/** Up to four decimals, for the 4-decimal cumulative shares */
export const fmtPct4 = (v: number) => `${nf(2, 4).format(v)}%`;
/** Axis ticks: 250000 -> "250K" */
export const fmtCompact = (v: number) => nf(0, 1, true).format(v);

const monthLong = new Intl.DateTimeFormat("en-US", { month: "short", year: "numeric", timeZone: "UTC" });
const monthShort = new Intl.DateTimeFormat("en-US", { month: "short", year: "2-digit", timeZone: "UTC" });
/** "2017-03-01" -> Date (UTC midnight) */
export const parseMonth = (s: string) => new Date(`${s}T00:00:00Z`);
/** "Mar 2017", or "Mar 17" when space is tight */
export const fmtMonth = (d: Date, short = false) => (short ? monthShort.format(d).replace(" ", " ’") : monthLong.format(d));

// ---------------------------------------------------------------- shapes
/** A column growing up from the baseline: 4px rounded data end, square base. */
export function columnPath(x: number, yTop: number, w: number, yBase: number, r = 4) {
  const h = yBase - yTop;
  if (h <= 0 || w <= 0) return "";
  const rr = Math.min(r, w / 2, h);
  return `M${x},${yBase}V${yTop + rr}A${rr},${rr} 0 0 1 ${x + rr},${yTop}H${x + w - rr}A${rr},${rr} 0 0 1 ${x + w},${yTop + rr}V${yBase}Z`;
}

/** A bar growing right from x0: rounded right end only when `roundEnd`. */
export function barPath(x0: number, x1: number, y: number, h: number, roundEnd = true, r = 4) {
  const w = x1 - x0;
  if (w <= 0 || h <= 0) return "";
  if (!roundEnd) return `M${x0},${y}H${x1}V${y + h}H${x0}Z`;
  const rr = Math.min(r, h / 2, w);
  return `M${x0},${y}H${x1 - rr}A${rr},${rr} 0 0 1 ${x1},${y + rr}V${y + h - rr}A${rr},${rr} 0 0 1 ${x1 - rr},${y + h}H${x0}Z`;
}

// ---------------------------------------------------------------- hooks
/**
 * Draw-in trigger: `drawn` turns true the first time the chart is mostly in
 * view. Under reduced motion it is true from the start and `instant` tells
 * marks to skip their animation, so the chart appears fully drawn.
 */
export function useDrawIn<T extends Element>() {
  const ref = useRef<T>(null);
  const reduce = !!useReducedMotion();
  const inView = useInView(ref, { once: true, amount: 0.35 });
  return { ref, drawn: reduce || inView, instant: reduce };
}

/** Motion props for a mark that grows in: scale from 0 on the given axis. */
export function growIn(axis: "x" | "y", drawn: boolean, instant: boolean, delay = 0, origin = axis === "y" ? "bottom" : "left") {
  const key = axis === "y" ? "scaleY" : "scaleX";
  return {
    initial: instant ? false : { [key]: 0 },
    animate: { [key]: drawn ? 1 : 0 },
    transition: instant ? { duration: 0 } : { duration: 0.7, delay, ease: [0.16, 1, 0.3, 1] as const },
    style: { transformBox: "fill-box" as const, transformOrigin: origin },
  };
}

export const PHONE_MAX = 639; // matches Tailwind's sm breakpoint (640px)
