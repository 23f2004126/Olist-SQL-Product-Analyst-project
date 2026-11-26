// Loads a chapter's charts. D3 and the chart components live in their own
// chunk (charts/FindingCharts), fetched after first paint, so the main
// bundle stays lean. While it loads, a quiet placeholder holds the space.
import { lazy, Suspense } from "react";
import { site } from "../../data/data";

const FindingCharts = lazy(() => import("../charts/FindingCharts"));

export function ChartsSlot({ chartIds }: { chartIds: string[] }) {
  return (
    <Suspense
      fallback={
        <div
          role="status"
          className="flex min-h-[420px] items-center justify-center rounded-[var(--radius-card)] border border-line bg-card/40 text-xs uppercase tracking-[0.18em] text-muted"
        >
          {site.ui.loading}…
        </div>
      }
    >
      <FindingCharts chartIds={chartIds} />
    </Suspense>
  );
}
