// Desktop only: a vertical chapter rail on the right. The line fills with
// reading progress; each dot jumps to its section; the current one is lit.
import { motion } from "framer-motion";
import { site } from "../../data/data";
import { sections } from "../../data/sections";
import { useActiveSection } from "../../hooks/useActiveSection";
import { useReadingProgress } from "../../hooks/useReadingProgress";
import { useScrollTo } from "../../hooks/SmoothScroll";

const ids = sections.map((s) => s.id);

export function ChapterRail() {
  const active = useActiveSection(ids);
  const scrollTo = useScrollTo();
  const { progress } = useReadingProgress();

  return (
    <nav
      aria-label={site.ui.progress}
      className="fixed right-6 top-1/2 z-30 hidden -translate-y-1/2 lg:block"
    >
      <div className="relative py-1">
        {/* progress line behind the dots */}
        <div className="absolute bottom-2 right-[5px] top-2 w-px bg-line" aria-hidden="true">
          <motion.div className="h-full w-full origin-top bg-accent/70" style={{ scaleY: progress }} />
        </div>
        <ol className="relative flex flex-col gap-4">
          {sections.map((s) => {
            const isActive = s.id === active;
            return (
              <li key={s.id}>
                <button
                  type="button"
                  onClick={() => scrollTo(s.id)}
                  aria-current={isActive ? "true" : undefined}
                  className="group flex w-full items-center justify-end gap-3"
                >
                  <span
                    className={`max-w-[11rem] truncate text-right text-xs transition-all duration-300 ${
                      isActive
                        ? "text-ink opacity-0 group-hover:opacity-100 group-focus-visible:opacity-100 xl:opacity-100"
                        : "text-muted opacity-0 group-hover:opacity-100 group-focus-visible:opacity-100"
                    }`}
                  >
                    {s.number && <span className="mr-1.5 text-accent">{s.number}</span>}
                    {s.short}
                  </span>
                  <span
                    aria-hidden="true"
                    className={`block h-[11px] w-[11px] rounded-full border transition-all duration-300 ${
                      isActive ? "border-accent bg-accent shadow-[var(--shadow-glow)]" : "border-line-strong bg-bg group-hover:border-accent"
                    }`}
                  />
                </button>
              </li>
            );
          })}
        </ol>
      </div>
    </nav>
  );
}
