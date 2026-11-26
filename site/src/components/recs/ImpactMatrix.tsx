// Impact against effort for R1-R3. Effort is read from docs/findings.md
// (recommendation details); impact is a stated judgement in site.json, and
// the chart says so on its axis and in the note under it.
// Both axes are ordinal (low / medium / high); the midlines split the plot
// into four quadrants.
import { findingsFile, site } from "../../data/data";
import type { Level } from "../../data/types";
import { useScrollTo } from "../../hooks/SmoothScroll";

// Where each level sits along an axis (share of the axis length, from the origin).
// High stays clear of the quadrant names in the top corners.
const AT: Record<Level, number> = { low: 0.22, medium: 0.58, high: 0.8 };

export function ImpactMatrix() {
  const m = site.recommendations.matrix;
  const scrollTo = useScrollTo();
  const points = findingsFile.recommendations.map((r) => ({
    id: r.id,
    title: r.title,
    effort: r.details.effort.toLowerCase() as Level,
    impact: m.impact[r.id],
  }));
  const levels = Object.keys(m.levels) as Level[];

  return (
    <figure className="glass m-0 p-5 sm:p-6">
      <figcaption className="mb-5 font-serif text-xl text-ink sm:text-2xl">{m.title}</figcaption>
      {/* two rows: [y title | y ticks | plot] and [ - | - | x ticks + x title] */}
      <div className="grid grid-cols-[auto_auto_minmax(0,1fr)] gap-x-2">
        <div className="flex w-5 items-center justify-center">
          <span className="rotate-180 text-xs whitespace-nowrap text-muted [writing-mode:vertical-rl]">{m.y_label}</span>
        </div>
        <div className="relative w-12 text-right text-xs text-muted sm:w-14" aria-hidden="true">
          {levels.map((l) => (
            <span key={l} className="absolute right-0 -translate-y-1/2" style={{ top: `${(1 - AT[l]) * 100}%` }}>
              {m.levels[l]}
            </span>
          ))}
        </div>
        <div className="relative aspect-square w-full rounded-lg border border-line sm:aspect-[16/9]">
          {/* quadrants: top-left is the quick-win corner */}
          <div aria-hidden="true" className="absolute inset-0 grid grid-cols-2 grid-rows-2 text-xs text-muted">
            <div className="border-r border-b border-line bg-accent/5 p-2.5 sm:p-3">{m.quadrants.quick_wins}</div>
            <div className="border-b border-line p-2.5 text-right sm:p-3">{m.quadrants.big_bets}</div>
            <div className="flex items-end border-r border-line p-2.5 sm:p-3">{m.quadrants.small_tweaks}</div>
            <div className="flex items-end justify-end p-2.5 text-right sm:p-3">{m.quadrants.deprioritise}</div>
          </div>
          {/* the three recommendations; each links to its card */}
          <ul>
            {points.map((p) => (
              <li
                key={p.id}
                className="absolute -translate-x-1/2 -translate-y-1/2"
                style={{ left: `${AT[p.effort] * 100}%`, top: `${(1 - AT[p.impact]) * 100}%` }}
              >
                <a
                  href={`#rec-${p.id}`}
                  onClick={(e) => {
                    e.preventDefault();
                    scrollTo(`rec-${p.id}`);
                  }}
                  aria-label={`${p.id}: ${p.title}. ${m.x_label} ${m.levels[p.effort]}, ${m.y_label} ${m.levels[p.impact]}.`}
                  className="group flex min-h-11 items-center gap-2 px-1"
                >
                  <span className="h-3.5 w-3.5 rounded-full bg-accent ring-4 ring-card transition-transform group-hover:scale-125" />
                  <span className="rounded-md bg-card/90 px-1.5 font-mono text-sm text-ink group-hover:text-accent">{p.id}</span>
                </a>
              </li>
            ))}
          </ul>
        </div>

        <div />
        <div />
        <div aria-hidden="true">
          <div className="relative mt-2 h-5 text-xs text-muted">
            {levels.map((l) => (
              <span key={l} className="absolute -translate-x-1/2" style={{ left: `${AT[l] * 100}%` }}>
                {m.levels[l]}
              </span>
            ))}
          </div>
          <p className="mt-1 text-center text-xs text-muted">{m.x_label}</p>
        </div>
      </div>

      {/* names of the points (identity is never position alone) */}
      <ul className="mt-5 space-y-1.5 text-sm">
        {points.map((p) => (
          <li key={p.id} className="flex gap-3">
            <span className="w-7 shrink-0 font-mono text-accent">{p.id}</span>
            <span className="text-ink/85">
              {p.title}{" "}
              <span className="text-muted">
({m.impact_word} {m.levels[p.impact].toLowerCase()}, {m.effort_word} {m.levels[p.effort].toLowerCase()})
              </span>
            </span>
          </li>
        ))}
      </ul>
      <p className="mt-4 border-t border-line pt-3 text-xs leading-relaxed text-muted">{m.note}</p>
    </figure>
  );
}
