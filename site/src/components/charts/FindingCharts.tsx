// Entry point of the lazily loaded chart chunk (D3 + every chart). Renders a
// chapter's charts, in the order site.json lists them, on a 12-column grid
// from the lg breakpoint; one column below it.
import type { ComponentType } from "react";
import { ConcentrationCurve } from "./ConcentrationCurve";
import { CohortHeatmap } from "./CohortHeatmap";
import { DelayHistogram } from "./DelayHistogram";
import { FreightBars } from "./FreightBars";
import { LowReviewBars } from "./LowReviewBars";
import { MonthlyMultiples } from "./MonthlyMultiples";
import { RepeatUnits } from "./RepeatUnits";
import { ReviewTimingSplit } from "./ReviewTimingSplit";
import { StageBars } from "./StageBars";

// Chart id -> component and its width on the 12-column grid.
const CHARTS: Record<string, { Chart: ComponentType; span: string }> = {
  repeat_units: { Chart: RepeatUnits, span: "lg:col-span-5" },
  cohort_matrix: { Chart: CohortHeatmap, span: "lg:col-span-7" },
  delay_buckets: { Chart: DelayHistogram, span: "lg:col-span-6" },
  stage_medians: { Chart: StageBars, span: "lg:col-span-6" },
  low_by_delay: { Chart: LowReviewBars, span: "lg:col-span-7" },
  late_review_timing: { Chart: ReviewTimingSplit, span: "lg:col-span-5" },
  seller_curve: { Chart: ConcentrationCurve, span: "lg:col-span-12" },
  monthly_multiples: { Chart: MonthlyMultiples, span: "lg:col-span-12" },
  freight_by_value: { Chart: FreightBars, span: "lg:col-span-12" },
};

export default function FindingCharts({ chartIds }: { chartIds: string[] }) {
  return (
    <div className="grid grid-cols-1 gap-4 sm:gap-5 lg:grid-cols-12">
      {chartIds.map((id) => {
        const entry = CHARTS[id];
        if (!entry) return null;
        const { Chart, span } = entry;
        return (
          <div key={id} className={`min-w-0 ${span}`}>
            <Chart />
          </div>
        );
      })}
    </div>
  );
}
