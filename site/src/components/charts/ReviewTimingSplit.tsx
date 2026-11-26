// F3b. Late orders split by when the review was written: before vs on/after
// delivery, with each group's average score and 1-2 star share
// (results/12_review_timing.csv, delivery_group = late).
// One whole split into two parts: a tall segmented bar, then the two groups.
import { motion } from "framer-motion";
import { useState } from "react";
import { ChartCard } from "./lib/ChartCard";
import { ChartTooltip, type TipState } from "./lib/Tooltip";
import { chartRows, fmt2, fmtInt, fmtPct, num, useDrawIn, useWidth } from "./lib/chartKit";
import { labelsFor } from "./lib/labels";

const ID = "late_review_timing";
// First row (reviewed before delivery) is the problem case: terracotta.
const FILLS = ["bg-late", "bg-slate"];

export function ReviewTimingSplit() {
  const rows = chartRows(ID);
  const { t, group } = labelsFor(ID);
  const timing = group("timing");
  const { ref, drawn, instant } = useDrawIn<HTMLDivElement>();
  const [box, width] = useWidth<HTMLDivElement>();
  const [tip, setTip] = useState<TipState | null>(null);
  const name = (r: (typeof rows)[number]) => timing[String(r.review_timing)] ?? String(r.review_timing);

  return (
    <ChartCard
      chartId={ID}
      table={{
        columns: [
          { label: t("group") },
          { label: t("orders"), numeric: true },
          { label: `${t("share")} (%)`, numeric: true },
          { label: t("avg"), numeric: true },
          { label: `${t("low")} (%)`, numeric: true },
        ],
        rows: rows.map((r) => [
          name(r),
          fmtInt(num(r.orders)),
          fmtPct(num(r.pct_within_delivery_group)),
          fmt2(num(r.avg_score)),
          fmtPct(num(r.low_review_pct)),
        ]),
      }}
    >
      <div ref={ref}>
        {/* tall segmented bar: widths are the shares, printed inside */}
        <div ref={box} className="relative" onPointerLeave={() => setTip(null)}>
        <div className="flex h-7 w-full gap-0.5" aria-hidden="true">
          {rows.map((r, i) => {
            const share = num(r.pct_within_delivery_group);
            const before = rows.slice(0, i).reduce((s, x) => s + num(x.pct_within_delivery_group), 0);
            return (
              <motion.div
                key={String(r.review_timing)}
                className={`${FILLS[i]} flex h-full min-w-0 items-center overflow-visible rounded-[4px] px-2`}
                style={{ flexBasis: `${share}%`, transformOrigin: "left" }}
                initial={instant ? false : { scaleX: 0 }}
                animate={{ scaleX: drawn ? 1 : 0 }}
                transition={instant ? { duration: 0 } : { duration: 0.8, delay: i * 0.2, ease: [0.16, 1, 0.3, 1] }}
                onPointerEnter={() =>
                  setTip({
                    x: (width * (before + share / 2)) / 100,
                    y: 0,
                    title: name(r),
                    rows: [
                      { label: t("share"), value: fmtPct(share) },
                      { label: t("orders"), value: fmtInt(num(r.orders)) },
                      { label: t("avg"), value: fmt2(num(r.avg_score)) },
                      { label: t("low"), value: fmtPct(num(r.low_review_pct)) },
                    ],
                  })
                }
              >
                {share >= 18 && (
                  <span className={`text-xs font-medium tabular-nums ${i === 0 ? "text-bg" : "text-ink"}`}>
                    {fmtPct(share)}
                  </span>
                )}
              </motion.div>
            );
          })}
        </div>
        <ChartTooltip tip={tip} width={width} />
        </div>

        {/* the two groups, side by side; values lead */}
        <dl className="mt-6 grid grid-cols-1 gap-4 min-[420px]:grid-cols-2">
          {rows.map((r, i) => (
            <motion.div
              key={String(r.review_timing)}
              className="rounded-xl border border-line p-4"
              initial={instant ? false : { opacity: 0, y: 6 }}
              animate={{ opacity: drawn ? 1 : 0, y: drawn ? 0 : 6 }}
              transition={{ duration: instant ? 0 : 0.5, delay: instant ? 0 : 0.5 + i * 0.15 }}
            >
              <dt className="flex items-center gap-2 text-xs text-muted">
                <span aria-hidden="true" className={`h-3 w-3 rounded-[3px] ${FILLS[i]}`} />
                {name(r)}
              </dt>
              <dd className="mt-3">
                <span className="block text-4xl font-semibold text-ink">{fmt2(num(r.avg_score))}</span>
                <span className="text-xs text-muted">{t("avg")}</span>
              </dd>
              <dd className="mt-3 flex justify-between gap-2 border-t border-line pt-2 text-xs">
                <span className="text-muted">{t("low")}</span>
                <span className="font-mono text-ink tabular-nums">{fmtPct(num(r.low_review_pct))}</span>
              </dd>
              <dd className="mt-1 flex justify-between gap-2 text-xs">
                <span className="text-muted">{t("orders")}</span>
                <span className="font-mono text-ink tabular-nums">{fmtInt(num(r.orders))}</span>
              </dd>
            </motion.div>
          ))}
        </dl>
      </div>
    </ChartCard>
  );
}
