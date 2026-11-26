// F1a. 100 dots for 100 customers; the dots for customers who came back on a
// later day are lit. The lit count is the later-day repeat rate rounded to a
// whole number (charts.json numbers.lit, derived from
// results/10_same_day_check.csv repeat_rate_later_day_pct).
import { motion } from "framer-motion";
import { useState } from "react";
import { charts } from "../../data/charts";
import { ChartCard, Legend, Swatch } from "./lib/ChartCard";
import { ChartTooltip, type TipState } from "./lib/Tooltip";
import { useDrawIn, useWidth } from "./lib/chartKit";
import { labelsFor } from "./lib/labels";

const ID = "repeat_units";
const COLS = 10; // a 10 x 10 grid: one dot per customer in 100
// Glow rings around a lit dot: [radius as a multiple of the dot's, fill opacity]
const GLOW: [number, number][] = [
  [2.4, 0.05],
  [1.9, 0.07],
  [1.5, 0.12],
];

export function RepeatUnits() {
  const copy = charts.items[ID];
  const { t } = labelsFor(ID);
  const n = copy.numbers;
  const total = COLS * COLS;
  const lit = n.lit.value;

  const [box, width] = useWidth<HTMLDivElement>();
  const { ref, drawn, instant } = useDrawIn<SVGSVGElement>();
  const [tip, setTip] = useState<TipState | null>(null);

  const size = Math.min(width, 320);
  const step = size / COLS;
  const r = Math.max(4, step * 0.3);
  const offsetX = (width - size) / 2;

  const litTip = (x: number, y: number): TipState => ({
    x,
    y,
    title: t("lit"),
    rows: [
      { label: n.returners.label, value: n.returners.display },
      { label: n.rate.label, value: n.rate.display },
    ],
  });
  const unlitTip = (x: number, y: number): TipState => ({
    x,
    y,
    title: t("unlit"),
    rows: [{ label: n.customers.label, value: n.customers.display }],
  });

  return (
    <ChartCard
      chartId={ID}
      legend={
        <Legend
          items={[
            { label: t("lit"), swatch: <Swatch shape="dot" className="bg-accent shadow-glow" /> },
            { label: t("unlit"), swatch: <Swatch shape="dot" className="bg-slate/60" /> },
          ]}
        />
      }
      table={{
        columns: [{ label: t("table_measure") }, { label: t("table_value"), numeric: true }],
        rows: [n.customers, n.returners, n.rate, n.lit].map((x) => [x.label, x.display]),
      }}
    >
      <div ref={box} className="relative" onPointerLeave={() => setTip(null)}>
        {width > 0 && (
          <svg ref={ref} width={width} height={size} className="block overflow-visible">
            {Array.from({ length: total }, (_, i) => {
              const isLit = i < lit; // lit dots first, top left, where the eye starts
              const cx = offsetX + (i % COLS) * step + step / 2;
              const cy = Math.floor(i / COLS) * step + step / 2;
              const row = Math.floor(i / COLS);
              // Unlit dots fade in row by row; lit dots light up after them.
              const delay = isLit ? 1.15 + i * 0.12 : row * 0.06;
              return (
                <g
                  key={i}
                  onPointerEnter={() => setTip(isLit ? litTip(cx, cy - r) : unlitTip(cx, cy - r))}
                >
                  {/* glow: faint rings that grow out (radius, not opacity, is animated,
                      so no compositing layer is created around them) */}
                  {isLit &&
                    GLOW.map(([k, o]) => (
                      <motion.circle
                        key={k}
                        cx={cx}
                        cy={cy}
                        className="fill-accent"
                        fillOpacity={o}
                        initial={instant ? false : { r: 0 }}
                        animate={{ r: drawn ? r * k : 0 }}
                        transition={{ duration: instant ? 0 : 0.8, delay: instant ? 0 : delay }}
                      />
                    ))}
                  <motion.circle
                    cx={cx}
                    cy={cy}
                    r={r}
                    className={isLit ? "fill-accent" : "fill-slate/60"}
                    initial={instant ? false : { opacity: 0, scale: 0.4 }}
                    animate={{ opacity: drawn ? 1 : 0, scale: drawn ? 1 : 0.4 }}
                    transition={{ duration: instant ? 0 : 0.5, delay: instant ? 0 : delay }}
                    style={{ transformBox: "fill-box", transformOrigin: "center" }}
                  />
                  {/* hit target: the whole grid cell */}
                  <rect x={cx - step / 2} y={cy - step / 2} width={step} height={step} fill="transparent" />
                </g>
              );
            })}
          </svg>
        )}
        <ChartTooltip tip={tip} width={width} />
      </div>
    </ChartCard>
  );
}
