// F3a. 1-2 star share by arrival against the promised date
// (results/12_by_delay_bucket.csv, the six delivery buckets).
import { BucketColumns } from "./lib/BucketColumns";
import { ChartCard, Legend, Swatch } from "./lib/ChartCard";
import { chartRows, fmt2, fmtInt, fmtPct, num } from "./lib/chartKit";
import { labelsFor } from "./lib/labels";

const ID = "low_by_delay";

export function LowReviewBars() {
  const rows = chartRows(ID);
  const { t } = labelsFor(ID);
  const data = rows.map((r) => ({
    bucket: String(r.bucket),
    value: num(r.low_review_pct),
    tip: [
      { label: t("low"), value: fmtPct(num(r.low_review_pct)) },
      { label: t("avg"), value: fmt2(num(r.avg_score)) },
      { label: t("orders"), value: fmtInt(num(r.orders)) },
    ],
  }));
  // Label the two ends of the rise, as the title does.
  const ends = data.length ? [data[0].bucket, data[data.length - 1].bucket] : [];

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
        columns: [
          { label: t("bucket") },
          { label: t("orders"), numeric: true },
          { label: t("avg"), numeric: true },
          { label: `${t("low")} (%)`, numeric: true },
        ],
        rows: rows.map((r) => [String(r.bucket), fmtInt(num(r.orders)), fmt2(num(r.avg_score)), fmtPct(num(r.low_review_pct))]),
      }}
    >
      <BucketColumns
        data={data}
        yLabel={t("y")}
        xLabel={t("x")}
        promisedLabel={t("promised")}
        format={fmtPct}
        labelled={ends}
      />
    </ChartCard>
  );
}
