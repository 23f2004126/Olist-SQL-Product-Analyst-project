// F5a. Small multiples of monthly orders, revenue and average order value
// (results/14_monthly_revenue.csv), Jan 2017 to Aug 2018. Same x-axis in
// every panel and every y-axis starts at zero, so the flat AOV line is plain.
// One crosshair runs through all three panels and one tooltip lists all three.
import { scaleLinear, scaleUtc } from "d3-scale";
import { area, line } from "d3-shape";
import { motion } from "framer-motion";
import { useState, type PointerEvent } from "react";
import { ChartCard } from "./lib/ChartCard";
import { ChartTooltip, type TipState } from "./lib/Tooltip";
import { chartRows, fmt2, fmtCompact, fmtInt, fmtMonth, num, parseMonth, useDrawIn, useWidth } from "./lib/chartKit";
import { labelsFor } from "./lib/labels";

const ID = "monthly_multiples";
const SERIES = [
  { col: "orders", format: fmtInt },
  { col: "revenue", format: fmt2 },
  { col: "aov", format: fmt2 },
] as const;

export function MonthlyMultiples() {
  const rows = chartRows(ID);
  const { t, group } = labelsFor(ID);
  const panels = group("panels");
  const months = rows.map((r) => parseMonth(String(r.purchase_month)));
  // Month under the pointer, and the panel the pointer is in (it gets the tooltip).
  const [hover, setHover] = useState<{ i: number; panel: number } | null>(null);
  const { ref, drawn, instant } = useDrawIn<HTMLDivElement>();

  const tipFor = (i: number) => ({
    title: fmtMonth(months[i]),
    rows: SERIES.map((s) => ({ label: panels[s.col], value: s.format(num(rows[i][s.col])), key: "bg-accent" })),
  });

  return (
    <ChartCard
      chartId={ID}
      table={{
        columns: [{ label: t("month") }, ...SERIES.map((s) => ({ label: panels[s.col], numeric: true }))],
        rows: rows.map((r, i) => [fmtMonth(months[i]), ...SERIES.map((s) => s.format(num(r[s.col])))]),
      }}
    >
      <div ref={ref} className="grid grid-cols-1 gap-6 md:grid-cols-3 md:gap-4">
        {SERIES.map((s, si) => (
          <Panel
            key={s.col}
            index={si}
            title={panels[s.col]}
            months={months}
            values={rows.map((r) => num(r[s.col]))}
            hover={hover}
            setHover={setHover}
            tipFor={tipFor}
            drawn={drawn}
            instant={instant}
            delay={si * 0.2}
          />
        ))}
      </div>
      <p className="mt-3 text-center text-xs text-muted">{t("x")}</p>
    </ChartCard>
  );
}

interface PanelProps {
  index: number;
  title: string;
  months: Date[];
  values: number[];
  hover: { i: number; panel: number } | null;
  setHover: (h: { i: number; panel: number } | null) => void;
  tipFor: (i: number) => Omit<TipState, "x" | "y">;
  drawn: boolean;
  instant: boolean;
  delay: number;
}

function Panel({ index, title, months, values, hover, setHover, tipFor, drawn, instant, delay }: PanelProps) {
  const [box, width] = useWidth<HTMLDivElement>();
  const height = 170;
  const m = { top: 10, right: 10, bottom: 24, left: 40 };
  const innerW = Math.max(0, width - m.left - m.right);
  const innerH = height - m.top - m.bottom;
  const x = scaleUtc().domain([months[0], months[months.length - 1]]).range([0, innerW]);
  const y = scaleLinear().domain([0, Math.max(...values)]).nice(3).range([innerH, 0]);
  const pts = values.map((v, i) => [x(months[i]), y(v)] as [number, number]);
  const path = line()(pts) ?? "";
  const fill = area().y0(innerH)(pts) ?? "";
  // Ticks at January and July; short labels ("Jan ’17") in narrow panels.
  const ticks = months.filter((d) => d.getUTCMonth() % 6 === 0);
  const short = innerW < 300;
  const last = pts[pts.length - 1];

  const onMove = (e: PointerEvent<SVGRectElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const t = x.invert(e.clientX - rect.left).getTime();
    let best = 0;
    months.forEach((d, i) => {
      if (Math.abs(d.getTime() - t) < Math.abs(months[best].getTime() - t)) best = i;
    });
    if (best !== hover?.i || hover?.panel !== index) setHover({ i: best, panel: index });
  };

  return (
    <div className="min-w-0">
      <p className="mb-2 text-xs font-medium text-ink">{title}</p>
      <div ref={box} className="relative" onPointerLeave={() => setHover(null)}>
        {width > 0 && (
          <svg width={width} height={height} className="block overflow-visible">
            <g transform={`translate(${m.left},${m.top})`}>
              {y.ticks(3).map((v) => (
                <g key={v} transform={`translate(0,${y(v)})`}>
                  <line x2={innerW} className="stroke-line" />
                  <text x={-8} dy="0.32em" textAnchor="end" className="fill-muted text-[12px] tabular-nums">
                    {fmtCompact(v)}
                  </text>
                </g>
              ))}
              {ticks.map((d) => (
                <text key={d.getTime()} x={x(d)} y={innerH + 18} textAnchor="middle" className="fill-muted text-[12px]">
                  {fmtMonth(d, short)}
                </text>
              ))}
              <motion.path
                d={fill}
                className="fill-accent"
                initial={instant ? false : { opacity: 0 }}
                animate={{ opacity: drawn ? 0.1 : 0 }}
                transition={{ duration: instant ? 0 : 0.8, delay: instant ? 0 : delay + 0.6 }}
              />
              <motion.path
                d={path}
                fill="none"
                className="stroke-accent"
                strokeWidth={2}
                strokeLinejoin="round"
                strokeLinecap="round"
                initial={instant ? false : { pathLength: 0 }}
                animate={{ pathLength: drawn ? 1 : 0 }}
                transition={{ duration: instant ? 0 : 1.2, delay: instant ? 0 : delay, ease: [0.16, 1, 0.3, 1] }}
              />
              {last && !hover && (
                <circle cx={last[0]} cy={last[1]} r={4} className="fill-accent stroke-card" strokeWidth={2} />
              )}
              {hover && (
                <g pointerEvents="none">
                  <line x1={pts[hover.i][0]} x2={pts[hover.i][0]} y1={0} y2={innerH} className="stroke-ink/40" />
                  <circle cx={pts[hover.i][0]} cy={pts[hover.i][1]} r={4} className="fill-accent stroke-card" strokeWidth={2} />
                </g>
              )}
              <line y1={innerH} y2={innerH} x2={innerW} className="stroke-line-strong" />
              <rect width={innerW} height={innerH} fill="transparent" onPointerMove={onMove} />
            </g>
          </svg>
        )}
        {/* the tooltip shows in the panel under the pointer only */}
        {hover?.panel === index && (
          <ChartTooltip tip={{ x: m.left + pts[hover.i][0], y: m.top + pts[hover.i][1], place: "side", ...tipFor(hover.i) }} width={width} />
        )}
      </div>
    </div>
  );
}
