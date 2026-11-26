// Section 8: how the analysis is built. The content (data model, data-quality
// decisions, SQL techniques) and its three data files load in their own chunk.
import { lazy, Suspense } from "react";
import { site } from "../../data/data";
import { Section } from "../layout/Section";

const HoodContent = lazy(() => import("./HoodContent"));

export function UnderTheHood() {
  const h = site.under_the_hood;
  return (
    <Section id="under-the-hood" label={h.label} title={h.title}>
      <Suspense
        fallback={
          <p role="status" className="min-h-[600px] text-sm text-muted">
            {site.ui.loading}…
          </p>
        }
      >
        <HoodContent />
      </Suspense>
    </Section>
  );
}
