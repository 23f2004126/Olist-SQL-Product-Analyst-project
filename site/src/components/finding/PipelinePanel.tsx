// "How we got this": each pipeline as a vertical funnel. One centred bar per
// step, its width proportional to the step's row count; the count sits on
// the bar (or beside it when the bar is too narrow), and the rows dropped at
// that step, with the reason, sit beside it. Steps animate in one after
// another when the panel opens (all at once under reduced motion). Below the
// funnel: the checks that passed for this finding, run by the export script.
import { motion, useReducedMotion } from "framer-motion";
import { useEffect, useRef, useState } from "react";
import { loadPipelines, pipelinesIfLoaded, site } from "../../data/data";
import type { PipelinesFile } from "../../data/types";

const fmt = (n: number) => n.toLocaleString("en-US");
const MIN_PCT = 0.8; // keep a sliver visible for tiny steps
const EASE = [0.16, 1, 0.3, 1] as const;

export function PipelinePanel({ findingId }: { findingId: string }) {
  // pipelines.json is fetched at idle time (see FindingChapter), so it is
  // usually ready when the panel opens.
  const [pipelines, setPipelines] = useState<PipelinesFile | null>(pipelinesIfLoaded);
  useEffect(() => {
    if (!pipelines) loadPipelines().then(setPipelines);
  }, [pipelines]);
  if (!pipelines) return <p className="text-sm text-muted">{site.ui.loading}…</p>;
  return <Funnel pipelines={pipelines} findingId={findingId} />;
}

function Funnel({ pipelines, findingId }: { pipelines: PipelinesFile; findingId: string }) {
  const steps = pipelines.pipelines[findingId] ?? [];
  const checks = pipelines.checks[findingId] ?? [];
  const first = steps[0]?.row_count ?? 1;
  const reduce = !!useReducedMotion();

  // Width of the bar track, to decide whether a count fits on its bar.
  const track = useRef<HTMLDivElement>(null);
  const [trackW, setTrackW] = useState(0);
  useEffect(() => {
    const el = track.current;
    if (!el) return;
    const ro = new ResizeObserver(([e]) => setTrackW(e.contentRect.width));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const list = {
    hidden: {},
    shown: { transition: { staggerChildren: reduce ? 0 : 0.14, delayChildren: reduce ? 0 : 0.1 } },
  };
  const item = {
    hidden: { opacity: 0, y: 6 },
    shown: { opacity: 1, y: 0, transition: { duration: reduce ? 0 : 0.45, ease: EASE } },
  };
  const bar = {
    hidden: { scaleX: 0 },
    shown: { scaleX: 1, transition: { duration: reduce ? 0 : 0.6, ease: EASE } },
  };

  return (
    <div>
      <motion.ol className="space-y-5" variants={list} initial={reduce ? false : "hidden"} animate="shown">
        {steps.map((s, i) => {
          const pct = Math.max(MIN_PCT, (100 * s.row_count) / first);
          const label = fmt(s.row_count);
          const barPx = (pct / 100) * trackW;
          const inside = barPx > label.length * 8 + 24;
          return (
            <motion.li
              key={s.step}
              variants={item}
              className="grid grid-cols-1 gap-x-6 gap-y-2 sm:grid-cols-[minmax(0,1fr)_13rem]"
            >
              <div className="min-w-0">
                <p className="mb-1.5 flex items-baseline gap-3 text-sm text-ink">
                  <span className="font-mono text-xs text-muted">
                    <span className="sr-only">{site.ui.step} </span>
                    {String(s.step).padStart(2, "0")}
                  </span>
                  {s.label}
                </p>
                <div ref={i === 0 ? track : undefined} className="relative h-8">
                  <motion.div
                    variants={bar}
                    aria-hidden="true"
                    className={`absolute inset-y-0 rounded-[4px] ${i === steps.length - 1 ? "bg-accent" : "bg-accent/70"}`}
                    style={{ width: `${pct}%`, left: `${(100 - pct) / 2}%`, originX: 0.5 }}
                  />
                  <span
                    className={`absolute top-1/2 -translate-y-1/2 font-mono text-sm whitespace-nowrap tabular-nums ${
                      inside ? "left-1/2 -translate-x-1/2 font-medium text-bg" : "text-accent"
                    }`}
                    style={inside ? undefined : { left: `calc(${50 + pct / 2}% + 10px)` }}
                  >
                    {label} <span className={inside ? "sr-only" : "text-muted"}>{site.ui.rows}</span>
                  </span>
                </div>
              </div>
              <div className="text-xs leading-relaxed text-muted sm:self-end sm:pb-1">
                {s.rows_dropped !== null && s.drop_reason ? (
                  <p>
                    <span className="font-mono text-late-text tabular-nums">−{fmt(s.rows_dropped)}</span> {site.ui.dropped}
                    <span className="block text-muted">{s.drop_reason}</span>
                  </p>
                ) : null}
              </div>
            </motion.li>
          );
        })}
      </motion.ol>

      {checks.length > 0 && (
        <motion.div
          className="mt-8 rounded-xl border border-line p-4"
          initial={reduce ? false : { opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: reduce ? 0 : 0.4, delay: reduce ? 0 : 0.14 * steps.length + 0.3 }}
        >
          <h4 className="mb-3 text-xs font-medium uppercase tracking-[0.18em] text-muted">{site.ui.checks_title}</h4>
          <ul className="space-y-2">
            {checks.map((c) => (
              <li key={c.text} className="flex gap-3 text-sm text-ink">
                <svg aria-hidden="true" viewBox="0 0 16 16" className="mt-0.5 h-4 w-4 shrink-0 text-accent">
                  <path d="M3 8.5l3.2 3L13 4.5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
                <span>{c.text}</span>
              </li>
            ))}
          </ul>
        </motion.div>
      )}

      <p className="mt-5 text-xs text-muted">
        {site.ui.source}: <span className="font-mono">{pipelines.source}</span>
      </p>
    </div>
  );
}
