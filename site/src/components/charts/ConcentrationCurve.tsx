// F4. Concentration curve: cumulative share of revenue against seller rank
// as a % of sellers. The curve comes from results/13_seller_revenue_rank.csv
// (sampled ranks, see charts.json seller_curve); the marked points at the
// top 1%, 5%, 10% and 20% come from results/13_concentration.csv, the
// numbers quoted in the chapter.
import { scaleLinear } from "d3-scale";
import { area, curveMonotoneX, line } from "d3-shape";
import { motion } from "framer-motion";
import { useState, type PointerEvent } from "react";
import { charts } from "../../data/charts";
import { ChartCard, Legend, Swatch } from "./lib/ChartCard";
import { ChartTooltip, type TipState } from "./lib/Tooltip";
import { chartRows, rowsOf, fmt2, fmtInt, fmtPct, fmtPct4, num, PHONE_MAX, useDrawIn, useWidth } from "./lib/chartKit";
import { labelsFor } from "./lib/labels";

const ID = "seller_curve";
const MARKS = "seller_concentration"; // charts.json rows for the marked points

export function ConcentrationCurve() {
  const copy = charts.items[ID];
  const { t } = labelsFor(ID);
  const total = copy.numbers.sellers.value;
  // (0, 0) is the curve's start: no sellers, no revenue.
  const points = [
    { rank: 0, x: 0, y: 0 },
    ...chartRows(ID).map((r) => ({ rank: num(r.revenue_rank), x: (100 * num(r.revenue_rank)) / total, y: num(r.cumulative_share_pct) })),
  ];
  const marks = rowsOf(copy.finding, MARKS).map((r) => ({
    top: num(r.top_pct),
    sellers: num(r.sellers_in_group),
    share: num(r.revenue_share_pct),
  }));

  const [box, width] = useWidth<HTMLDivElement>();
  const { ref, drawn, instant } = useDrawIn<SVGSVGElement>();
  const [tip, setTip] = useState<TipState | null>(null);
  const [hoverI, setHoverI] = useState<number | null>(null);

  const phone = width <= PHONE_MAX;
  const narrow = width < 560; // too narrow to pin the tooltip clear of the labels
  const height = phone ? 280 : 340;
  const m = { top: 30, right: 12, bottom: 44, left: 40 };
  const innerW = Math.max(0, width - m.left - m.right);
  const innerH = height - m.top - m.bottom;
  const x = scaleLinear().domain([0, 100]).range([0, innerW]);
  const y = scaleLinear().domain([0, 100]).range([innerH, 0]);
  const path = line<(typeof points)[number]>().x((p) => x(p.x)).y((p) => y(p.y)).curve(curveMonotoneX)(points) ?? "";
  const fill = area<(typeof points)[number]>().x((p) => x(p.x)).y0(innerH).y1((p) => y(p.y)).curve(curveMonotoneX)(points) ?? "";

  // Crosshair: snap to the nearest sampled rank.
  const onMove = (e: PointerEvent<SVGRectElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const xv = x.invert(e.clientX - rect.left);
    let best = 1;
    for (let i = 1; i < points.length; i++) if (Math.abs(points[i].x - xv) < Math.abs(points[best].x - xv)) best = i;
    if (best === hoverI) return;
    const p = points[best];
    setHoverI(best);
    // Never over the marker labels: on wide charts it is pinned to the plot's
    // lower-right corner (empty under a concave curve, right of every label);
    // on narrow ones it is a readout under the chart.
    setTip({
      x: m.left + innerW - 8,
      y: m.top + innerH - 8,
      place: narrow ? "static" : "corner",
      title: `${t("top")} ${fmt2(p.x)}%`,
      rows: [
        { label: t("sellers"), value: fmtInt(p.rank) },
        { label: t("share"), value: fmtPct4(p.y), key: "bg-accent" },
      ],
    });
  };
  const hp = hoverI !== null ? points[hoverI] : null;

  return (
    <ChartCard
      chartId={ID}
      legend={
        <Legend
          items={[
            { label: t("y"), swatch: <Swatch shape="line" className="bg-accent" /> },
            { label: t("equal"), swatch: <Swatch shape="line" className="bg-slate" /> },
          ]}
        />
      }
      table={{
        columns: [{ label: t("table_top") }, { label: t("sellers"), numeric: true }, { label: `${t("share")} (%)`, numeric: true }],
        rows: marks.map((mk) => [`${t("top")} ${mk.top}%`, fmtInt(mk.sellers), fmtPct(mk.share)]),
        note: t("table_note"),
      }}
    >
      <div ref={box} className="relative" onPointerLeave={() => (setTip(null), setHoverI(null))}>
        {width > 0 && (
          <svg ref={ref} width={width} height={height} className="block overflow-visible">
            <g transform={`translate(${m.left},${m.top})`}>
              {y.ticks(4).map((v) => (
                <g key={v} transform={`translate(0,${y(v)})`}>
                  <line x2={innerW} className="stroke-line" />
                  <text x={-8} dy="0.32em" textAnchor="end" className="fill-muted text-[12px] tabular-nums">
                    {v}%
                  </text>
                </g>
              ))}
              {x.ticks(phone ? 4 : 5).map((v) => (
                <text key={v} x={x(v)} y={innerH + 18} textAnchor="middle" className="fill-muted text-[12px] tabular-nums">
                  {v}%
                </text>
              ))}
              <text x={-m.left} y={-16} className="fill-muted text-[12px]">
                {t("y")}
              </text>

              {/* reference: every seller earning the same share */}
              <line x1={x(0)} y1={y(0)} x2={x(100)} y2={y(100)} className="stroke-slate" />

              <motion.path
                d={fill}
                className="fill-accent"
                initial={instant ? false : { opacity: 0 }}
                animate={{ opacity: drawn ? 0.1 : 0 }}
                transition={{ duration: instant ? 0 : 0.8, delay: instant ? 0 : 0.6 }}
              />
              <motion.path
                d={path}
                fill="none"
                className="stroke-accent"
                strokeWidth={2}
                strokeLinecap="round"
                strokeLinejoin="round"
                initial={instant ? false : { pathLength: 0 }}
                animate={{ pathLength: drawn ? 1 : 0 }}
                transition={{ duration: instant ? 0 : 1.4, ease: [0.16, 1, 0.3, 1] }}
              />

              {hp && (
                <g pointerEvents="none">
                  <line x1={x(hp.x)} x2={x(hp.x)} y1={0} y2={innerH} className="stroke-ink/40" />
                  <circle cx={x(hp.x)} cy={y(hp.y)} r={4} className="fill-accent stroke-card" strokeWidth={2} />
                </g>
              )}

              {/* marked points with direct labels, below-right of the curve */}
              {marks.map((mk, i) => (
                <motion.g
                  key={mk.top}
                  initial={instant ? false : { opacity: 0 }}
                  animate={{ opacity: drawn ? 1 : 0 }}
                  transition={{ duration: instant ? 0 : 0.4, delay: instant ? 0 : 0.9 + i * 0.15 }}
                  pointerEvents="none"
                >
                  <circle cx={x(mk.top)} cy={y(mk.share)} r={5} className="fill-accent stroke-card" strokeWidth={2} />
                  <text x={x(mk.top) + 10} y={y(mk.share) + 16} className="fill-ink text-[12px] tabular-nums">
                    {t("top")} {mk.top}%<tspan className="fill-muted"> · {fmtPct(mk.share)}</tspan>
                  </text>
                </motion.g>
              ))}

              <line y1={innerH} y2={innerH} x2={innerW} className="stroke-line-strong" />
              <rect width={innerW} height={innerH} fill="transparent" onPointerMove={onMove} />
            </g>
            <text x={m.left + innerW / 2} y={height - 4} textAnchor="middle" className="fill-muted text-[12px]">
              {t("x")}
            </text>
          </svg>
        )}
        {narrow ? (
          // reserved space, so the card does not jump when the readout appears
          <div className="mt-3 min-h-[5.25rem]">{tip && <ChartTooltip tip={tip} width={width} />}</div>
        ) : (
          <ChartTooltip tip={tip} width={width} />
        )}
      </div>
    </ChartCard>
  );
}
