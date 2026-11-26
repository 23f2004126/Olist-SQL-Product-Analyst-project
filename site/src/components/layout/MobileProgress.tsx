// Mobile and tablet: a thin reading-progress bar under the top bar, with the
// current chapter name. Hidden on desktop, where the chapter rail takes over.
import { motion } from "framer-motion";
import { site } from "../../data/data";
import { sections } from "../../data/sections";
import { useActiveSection } from "../../hooks/useActiveSection";
import { useReadingProgress } from "../../hooks/useReadingProgress";

const ids = sections.map((s) => s.id);

export function MobileProgress() {
  const { progress, percent } = useReadingProgress();
  const activeId = useActiveSection(ids); // hooks must run at the top level, never inside callbacks
  const active = sections.find((s) => s.id === activeId);

  return (
    <div className="lg:hidden">
      <div
        className="h-0.5 w-full bg-line"
        role="progressbar"
        aria-label={site.ui.progress}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={percent}
      >
        <motion.div className="h-full origin-left bg-accent" style={{ scaleX: progress }} />
      </div>
      {active && active.id !== "top" && (
        <p className="mx-auto max-w-6xl truncate px-4 py-1.5 text-[11px] uppercase tracking-[0.18em] text-muted sm:px-6">
          {active.number && <span className="mr-2 text-accent">{active.number}</span>}
          {active.short}
        </p>
      )}
    </div>
  );
}
