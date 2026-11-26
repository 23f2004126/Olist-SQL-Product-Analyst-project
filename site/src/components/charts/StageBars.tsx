// F2b. Stage breakdown: one stacked bar each for late and on-time orders,
// split into the three stages by median days (results/11_stage_medians.csv).
// Both bars share one day scale, so the late bar's length shows the gap.
// Stages are an ordered sequence, so they are steps of the bar's own colour
// (terracotta for late, champagne for on time), lightest first.
import { scaleLinear } from "d3-scale";
import { motion } from "framer-motion";
import { useState } from "react";
import { ChartCard, Legend } from "./lib/ChartCard";
import { ChartTooltip, type TipState } from "./lib/Tooltip";
import { barPath, chartRows, fmt2, fmtInt, num, useDrawIn, useWidth } from "./lib/chartKit";
import { labelsFor } from "./lib/labels";

const ID = "stage_medians";
const STEP_OPACITY = [0.3, 0.5, 1]; // stage 1 -> 3
const GAP = 2; // surface gap between segments
const BAR_H = 28;

export function StageBars() {
  const rows = chartRows(ID);
  const { t, group } = labelsFor(ID);
  const stages = group("stages"); // column -> stage name, in stage order
  const stageCols = Object.keys(stages);
  const groups = group("groups");

  const [box, width] = useWidth<HTMLDivElement>();
  const { ref, drawn, instant } = useDrawIn<SVGSVGElement>();
  const [tip, setTip] = useState<TipState | null>(null);
  const [active, setActive] = useState<string | null>(null);

  const totals = rows.map((r) => stageCols.reduce((s, c) => s + num(r[c]), 0));
  const m = { top: 4, right: 14, bottom: 40, left: 10 };
  const innerW = Math.max(0, width - m.left - m.right);
  const rowGap = 30; // room for the row label above each bar
  const innerH = rows.length * (BAR_H + rowGap);
  const height = innerH + m.top + m.bottom;
  const x = scaleLinear().domain([0, Math.max(...totals)]).nice(5).range([0, innerW]);

  return (
    <ChartCard
      chartId={ID}
      legend={
        <Legend
          items={stageCols.map((c, i) => ({
            label: stages[c],
            swatch: (
              <span className="flex gap-0.5">
                <span className="h-3 w-1.5 rounded-l-[2px] bg-accent" style={{ opacity: STEP_OPACITY[i] }} />
                <span className="h-3 w-1.5 rounded-r-[2px] bg-late" style={{ opacity: STEP_OPACITY[i] }} />
              </span>
            ),
          }))}
        />
      }
      table={{
        columns: [
          { label: t("group") },
          { label: t("orders"), numeric: true },
          ...stageCols.map((c) => ({ label: `${stages[c]} (${t("x").toLowerCase()})`, numeric: true })),
        ],
        rows: rows.map((r) => [groups[String(r.delivery_group)] ?? String(r.delivery_group), fmtInt(num(r.orders)), ...stageCols.map((c) => fmt2(num(r[c])))]),
      }}
    >
      <div ref={box} className="relative" onPointerLeave={() => (setTip(null), setActive(null))}>
        {width > 0 && (
          <svg ref={ref} width={width} height={height} className="block">
            <g transform={`translate(${m.left},${m.top})`}>
              {x.ticks(5).map((v) => (
                <g key={v} transform={`translate(${x(v)},0)`}>
                  <line y1={0} y2={innerH} className="stroke-line" />
                  <text y={innerH + 16} textAnchor="middle" className="fill-muted text-[12px] tabular-nums">
                    {v}
                  </text>
                </g>
              ))}
              {rows.map((r, ri) => {
                const g = String(r.delivery_group);
                const late = g === "late";
                const top = ri * (BAR_H + rowGap) + rowGap - 8;
                let x0 = 0;
                return (
                  <g key={g}>
                    <text x={0} y={top - 8} className="fill-ink text-[12px]">
                      {groups[g] ?? g}
                      <tspan className="fill-muted"> · {fmtInt(num(r.orders))}</tspan>
                    </text>
                    {stageCols.map((c, si) => {
                      const v = num(r[c]);
                      const a = x(x0);
                      x0 += v;
                      const b = x(x0);
                      const last = si === stageCols.length - 1;
                      // 2px surface gap after every segment but the last
                      const end = last ? b : Math.max(a, b - GAP);
                      const key = `${g}-${c}`;
                      const label = fmt2(v);
                      const fits = end - a > label.length * 7.5 + 12;
                      const solid = STEP_OPACITY[si] === 1;
                      return (
                        <g key={c}>
                          <motion.path
                            d={barPath(a, end, top, BAR_H, last)}
                            className={late ? "fill-late" : "fill-accent"}
                            fillOpacity={STEP_OPACITY[si]}
                            opacity={active && active !== key ? 0.55 : 1}
                            {...growIn(drawn, instant, ri * 0.15)}
                          />
                          {fits && (
                            <motion.text
                              x={a + 8}
                              y={top + BAR_H / 2}
                              dy="0.34em"
                              className={`text-[12px] font-medium tabular-nums ${solid ? "fill-bg" : "fill-ink"}`}
                              initial={instant ? false : { opacity: 0 }}
                              animate={{ opacity: drawn ? 1 : 0 }}
                              transition={{ duration: instant ? 0 : 0.3, delay: instant ? 0 : 0.6 + ri * 0.15 }}
                            >
                              {label}
                            </motion.text>
                          )}
                          {/* hit target: the segment plus the row label band (at least 6px wide) */}
                          <rect
                            x={a}
                            y={top - 4}
                            width={Math.max(6, b - a)}
                            height={BAR_H + 8}
                            fill="transparent"
                            onPointerEnter={() => {
                              setActive(key);
                              setTip({
                                x: m.left + (a + b) / 2,
                                y: m.top + top,
                                title: `${groups[g] ?? g}: ${stages[c]}`,
                                rows: [
                                  { label: t("x"), value: fmt2(v) },
                                  { label: t("orders"), value: fmtInt(num(r.orders)) },
                                ],
                              });
                            }}
                          />
                        </g>
                      );
                    })}
                  </g>
                );
              })}
            </g>
            <text x={m.left + innerW / 2} y={height - 4} textAnchor="middle" className="fill-muted text-[12px]">
              {t("x")}
            </text>
          </svg>
        )}
        <ChartTooltip tip={tip} width={width} />
      </div>
    </ChartCard>
  );
}

/** Segments of one bar grow together from the left edge of the chart. */
function growIn(drawn: boolean, instant: boolean, delay: number) {
  return {
    initial: instant ? false : { scaleX: 0 },
    animate: { scaleX: drawn ? 1 : 0 },
    transition: instant ? { duration: 0 } : { duration: 0.8, delay, ease: [0.16, 1, 0.3, 1] as const },
    style: { transformOrigin: "0px 0px" },
  };
}
