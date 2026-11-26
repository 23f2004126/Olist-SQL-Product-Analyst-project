// F5b. Freight as a share of item value by order-value quartile
// (results/14_freight_by_value_quartile.csv). Horizontal bars so each
// quartile's value range fits as a label above its bar, phone or desktop.
import { scaleLinear } from "d3-scale";
import { motion } from "framer-motion";
import { useState } from "react";
import { ChartCard } from "./lib/ChartCard";
import { ChartTooltip, type TipState } from "./lib/Tooltip";
import { barPath, chartRows, fmt2, fmtInt, fmtPct, num, useDrawIn, useWidth } from "./lib/chartKit";
import { labelsFor } from "./lib/labels";

const ID = "freight_by_value";
const BAR_H = 22;
const ROW = 58; // label line + bar + gap

export function FreightBars() {
  const rows = chartRows(ID);
  const { t } = labelsFor(ID);
  const [box, width] = useWidth<HTMLDivElement>();
  const { ref, drawn, instant } = useDrawIn<SVGSVGElement>();
  const [tip, setTip] = useState<TipState | null>(null);
  const [active, setActive] = useState<number | null>(null);

  const values = rows.map((r) => num(r.freight_pct_of_item_value));
  const labelRoom = 64; // value printed past the bar end
  const height = rows.length * ROW + 30;
  const x = scaleLinear().domain([0, Math.max(...values)]).range([0, Math.max(0, width - labelRoom)]);
  const name = (r: (typeof rows)[number]) => `${t("quartile_prefix")}${r.value_quartile}`;
  const range = (r: (typeof rows)[number]) => `${fmt2(num(r.min_order_value))}–${fmt2(num(r.max_order_value))}`;

  return (
    <ChartCard
      chartId={ID}
      table={{
        columns: [
          { label: t("quartile") },
          { label: t("range") },
          { label: t("orders"), numeric: true },
          { label: `${t("freight")} (%)`, numeric: true },
          { label: `${t("gt50")} (%)`, numeric: true },
        ],
        rows: rows.map((r) => [name(r), range(r), fmtInt(num(r.orders)), fmtPct(num(r.freight_pct_of_item_value)), fmtPct(num(r.pct_orders_freight_gt_50))]),
      }}
    >
      <div ref={box} className="relative max-w-2xl" onPointerLeave={() => (setTip(null), setActive(null))}>
        {width > 0 && (
          <svg ref={ref} width={width} height={height} className="block">
            {rows.map((r, i) => {
              const v = values[i];
              const top = i * ROW + 22;
              return (
                <g key={String(r.value_quartile)} opacity={active !== null && active !== i ? 0.55 : 1}>
                  <text x={0} y={top - 8} className="fill-ink text-[12px]">
                    {name(r)}
                    <tspan className="fill-muted">
                      {" · "}
                      {range(r)} {t("currency")}
                    </tspan>
                  </text>
                  <motion.path
                    d={barPath(0, x(v), top, BAR_H)}
                    className="fill-accent"
                    initial={instant ? false : { scaleX: 0 }}
                    animate={{ scaleX: drawn ? 1 : 0 }}
                    transition={instant ? { duration: 0 } : { duration: 0.8, delay: i * 0.1, ease: [0.16, 1, 0.3, 1] }}
                    style={{ transformOrigin: "0px 0px" }}
                  />
                  <motion.text
                    x={x(v) + 8}
                    y={top + BAR_H / 2}
                    dy="0.34em"
                    className="fill-ink text-[12px] font-medium tabular-nums"
                    initial={instant ? false : { opacity: 0 }}
                    animate={{ opacity: drawn ? 1 : 0 }}
                    transition={{ duration: instant ? 0 : 0.3, delay: instant ? 0 : 0.6 + i * 0.1 }}
                  >
                    {fmtPct(v)}
                  </motion.text>
                  <rect
                    x={0}
                    y={top - 22}
                    width={width}
                    height={ROW - 4}
                    fill="transparent"
                    onPointerEnter={() => {
                      setActive(i);
                      setTip({
                        x: x(v) / 2,
                        y: top,
                        title: `${name(r)} · ${range(r)}`,
                        rows: [
                          { label: t("freight"), value: fmtPct(v) },
                          { label: t("gt50"), value: fmtPct(num(r.pct_orders_freight_gt_50)) },
                          { label: t("orders"), value: fmtInt(num(r.orders)) },
                        ],
                      });
                    }}
                  />
                </g>
              );
            })}
            <text x={0} y={height - 4} className="fill-muted text-[12px]">
              {t("x")}
            </text>
          </svg>
        )}
        <ChartTooltip tip={tip} width={width} />
      </div>
    </ChartCard>
  );
}
