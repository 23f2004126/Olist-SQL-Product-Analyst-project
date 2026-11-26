// F2a. Promise vs reality: delivered orders by arrival against the promised
// date (results/11_delay_buckets.csv), with a line at the promised date.
import { BucketColumns } from "./lib/BucketColumns";
import { ChartCard, Legend, Swatch } from "./lib/ChartCard";
import { chartRows, fmtInt, fmtPct, num } from "./lib/chartKit";
import { labelsFor } from "./lib/labels";

const ID = "delay_buckets";

export function DelayHistogram() {
  const rows = chartRows(ID);
  const { t } = labelsFor(ID);
  const data = rows.map((r) => ({
    bucket: String(r.bucket),
    value: num(r.pct_of_orders),
    tip: [
      { label: t("share"), value: fmtPct(num(r.pct_of_orders)) },
      { label: t("orders"), value: fmtInt(num(r.orders)) },
    ],
  }));
  // Label only the biggest column; the tooltip and table carry the rest.
  const top = data.reduce((a, b) => (b.value > a.value ? b : a), data[0]);

  return (
    <ChartCard
      chartId={ID}
      legend={
        <Legend
          items={[
            { label: t("on_time"), swatch: <Swatch className="bg-accent" /> },
            { label: t("late"), swatch: <Swatch className="bg-late" /> },
          ]}
        />
      }
      table={{
        columns: [{ label: t("bucket") }, { label: t("orders"), numeric: true }, { label: `${t("share")} (%)`, numeric: true }],
        rows: rows.map((r) => [String(r.bucket), fmtInt(num(r.orders)), fmtPct(num(r.pct_of_orders))]),
      }}
    >
      <BucketColumns
        data={data}
        yLabel={t("y")}
        xLabel={t("x")}
        promisedLabel={t("promised")}
        format={fmtPct}
        labelled={top ? [top.bucket] : []}
      />
    </ChartCard>
  );
}
