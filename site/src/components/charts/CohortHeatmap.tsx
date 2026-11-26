// F1b. Cohort heatmap: first-order month (rows) by months since first order
// (0-12), coloured by the share of the cohort ordering that month
// (results/10_cohort_matrix_pct.csv). NULL cells (months the data had not
// reached) are left empty, not drawn as zero. Month 0 is always 100%, so it
// is drawn in slate as a reference and kept off the colour scale.
import { scaleBand, scaleSqrt } from "d3-scale";
import { motion } from "framer-motion";
import { useState, type PointerEvent } from "react";
import { charts } from "../../data/charts";
import { ChartCard, Legend, Swatch } from "./lib/ChartCard";
import { ChartTooltip, type TipState } from "./lib/Tooltip";
import { chartRows, fmtInt, fmtMonth, fmtPct, parseMonth, PHONE_MAX, useDrawIn, useWidth } from "./lib/chartKit";
import { labelsFor } from "./lib/labels";

const ID = "cohort_matrix";
const MONTHS = 13; // columns m0..m12 in the query output

export function CohortHeatmap() {
  const rows = chartRows(ID);
  const { t } = labelsFor(ID);
  const empty = charts.ui.not_observed;
  const [box, width] = useWidth<HTMLDivElement>();
  const { ref, drawn, instant } = useDrawIn<SVGSVGElement>();
  const [tip, setTip] = useState<TipState | null>(null);
  const [hover, setHover] = useState<[number, number] | null>(null);

  const phone = width <= PHONE_MAX - 160;
  const cols = Array.from({ length: MONTHS }, (_, i) => `m${i}`);
  const cohorts = rows.map((r) => String(r.cohort_month));
  const cell = (ri: number, ci: number) => {
    const v = rows[ri][cols[ci]];
    return typeof v === "number" ? v : null;
  };
  const later = rows.flatMap((_, ri) => cols.slice(1).map((_, k) => cell(ri, k + 1))).filter((v): v is number => v !== null);
  const lo = Math.min(...later);
  const hi = Math.max(...later);
  // Square-root scale: small shares still separate, one hue light to dark.
  const opacity = scaleSqrt().domain([lo, hi]).range([0.1, 1]);

  const m = { top: 8, right: 4, bottom: 40, left: phone ? 54 : 70 };
  const innerW = Math.max(0, width - m.left - m.right);
  const rowH = phone ? 16 : 18;
  const innerH = rowH * rows.length;
  const height = innerH + m.top + m.bottom;
  const x = scaleBand<number>().domain(cols.map((_, i) => i)).range([0, innerW]).paddingInner(0.1);
  const y = scaleBand<number>().domain(rows.map((_, i) => i)).range([0, innerH]).paddingInner(0.12);

  const onMove = (e: PointerEvent<SVGRectElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const ci = Math.min(MONTHS - 1, Math.max(0, Math.floor(((e.clientX - rect.left) / rect.width) * MONTHS)));
    const ri = Math.min(rows.length - 1, Math.max(0, Math.floor(((e.clientY - rect.top) / rect.height) * rows.length)));
    if (hover && hover[0] === ri && hover[1] === ci) return;
    setHover([ri, ci]);
    const v = cell(ri, ci);
    setTip({
      x: m.left + (x(ci) ?? 0) + x.bandwidth() / 2,
      y: m.top + (y(ri) ?? 0),
      title: `${t("cohort")} ${fmtMonth(parseMonth(cohorts[ri]))}`,
      rows: [
        { label: t("customers"), value: fmtInt(Number(rows[ri].cohort_customers)) },
        { label: t("month"), value: String(ci) },
        { label: t("share"), value: v === null ? empty : fmtPct(v) },
      ],
    });
  };

  return (
    <ChartCard
      chartId={ID}
      legend={
        <div className="space-y-3">
          <div className="flex items-center gap-3 text-xs text-muted">
            <span className="font-mono tabular-nums">{fmtPct(lo)}</span>
            <span
              aria-hidden="true"
              className="h-2.5 w-28 rounded-full"
              style={{
                background: "linear-gradient(90deg, color-mix(in srgb, var(--color-accent) 10%, var(--color-card)), var(--color-accent))",
              }}
            />
            <span className="font-mono tabular-nums">{fmtPct(hi)}</span>
            <span>{t("scale")}</span>
          </div>
          <Legend
            items={[
              { label: t("month0"), swatch: <Swatch className="bg-slate" /> },
              { label: t("blank"), swatch: <Swatch shape="outline" className="border-line-strong" /> },
            ]}
          />
        </div>
      }
      table={{
        columns: [
          { label: t("y") },
          { label: t("customers"), numeric: true },
          ...cols.map((_, i) => ({ label: `${t("month_prefix")}${i} (%)`, numeric: true })),
        ],
        rows: rows.map((r, ri) => [
          fmtMonth(parseMonth(cohorts[ri])),
          fmtInt(Number(r.cohort_customers)),
          ...cols.map((_, ci) => {
            const v = cell(ri, ci);
            return v === null ? empty : fmtPct(v);
          }),
        ]),
      }}
    >
      <div ref={box} className="relative" onPointerLeave={() => (setTip(null), setHover(null))}>
        {width > 0 && (
          <svg ref={ref} width={width} height={height} className="block">
            <g transform={`translate(${m.left},${m.top})`}>
              {rows.map((_, ri) => (
                <text
                  key={ri}
                  x={-8}
                  y={(y(ri) ?? 0) + y.bandwidth() / 2}
                  dy="0.32em"
                  textAnchor="end"
                  className="fill-muted text-[12px] tabular-nums"
                >
                  {fmtMonth(parseMonth(cohorts[ri]), phone)}
                </text>
              ))}
              {rows.map((_, ri) =>
                cols.map((_, ci) => {
                  const v = cell(ri, ci);
                  if (v === null) return null; // not observable yet: leave the cell empty
                  const isHover = hover?.[0] === ri && hover?.[1] === ci;
                  return (
                    <motion.rect
                      key={`${ri}-${ci}`}
                      x={x(ci)}
                      y={y(ri)}
                      width={x.bandwidth()}
                      height={y.bandwidth()}
                      rx={2}
                      className={`${ci === 0 ? "fill-slate" : "fill-accent"} ${isHover ? "stroke-ink" : ""}`}
                      strokeWidth={isHover ? 1.5 : 0}
                      initial={instant ? false : { opacity: 0 }}
                      animate={{ opacity: drawn ? (ci === 0 ? 1 : opacity(v)) : 0 }}
                      transition={{ duration: instant ? 0 : 0.45, delay: instant ? 0 : ci * 0.06 + ri * 0.012 }}
                    />
                  );
                }),
              )}
              {cols.map((_, ci) => (
                <text
                  key={ci}
                  x={(x(ci) ?? 0) + x.bandwidth() / 2}
                  y={innerH + 16}
                  textAnchor="middle"
                  className="fill-muted text-[12px] tabular-nums"
                >
                  {ci}
                </text>
              ))}
              {/* one hit layer for the whole grid; the cell is found from the pointer */}
              <rect width={innerW} height={innerH} fill="transparent" onPointerMove={onMove} />
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
