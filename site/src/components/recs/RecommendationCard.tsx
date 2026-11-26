// One recommendation: change, evidence (sourced numbers), target metric and
// direction, test design, risk and effort.
import { site } from "../../data/data";
import { chapterNumber } from "../../data/sections";
import type { Recommendation } from "../../data/types";
import { useScrollTo } from "../../hooks/SmoothScroll";
import { GlassCard } from "../ui/GlassCard";

/** Links back to the finding chapters that are this recommendation's evidence. */
function EvidenceLinks({ findings }: { findings: string[] }) {
  const scrollTo = useScrollTo();
  return (
    <p className="mt-3 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-muted">
      <span>{site.recommendations.evidence_in}</span>
      {findings.map((fid) => {
        const i = site.chapters.findIndex((c) => c.id === fid);
        const ch = site.chapters[i];
        if (!ch) return null;
        return (
          <a
            key={fid}
            href={`#chapter-${fid}`}
            onClick={(e) => {
              e.preventDefault();
              scrollTo(`chapter-${fid}`);
            }}
            className="inline-flex min-h-8 items-center gap-1.5 rounded-full border border-line px-3 text-ink transition-colors hover:border-accent hover:text-accent"
          >
            <span className="font-mono text-xs text-accent">{chapterNumber(i)}</span>
            {ch.title}
          </a>
        );
      })}
    </p>
  );
}

// A dt/dd pair. The wrapper div is the only allowed level between <dl> and
// its dt/dd, so layout classes go on it rather than on an extra div.
function Field({ label, className, children }: { label: string; className?: string; children: React.ReactNode }) {
  return (
    <div className={className}>
      <dt className="mb-1.5 text-xs font-medium uppercase tracking-[0.18em] text-muted">{label}</dt>
      <dd className="text-sm leading-relaxed text-ink/90">{children}</dd>
    </div>
  );
}

export function RecommendationCard({ rec }: { rec: Recommendation }) {
  const ui = site.ui;
  const d = rec.details;

  return (
    <GlassCard className="p-6 sm:p-8">
      <article>
        <header className="mb-6 flex flex-wrap items-start justify-between gap-4">
          <div className="max-w-2xl">
            <p className="mb-2 font-mono text-xs text-accent">{rec.id}</p>
            <h3 className="font-serif text-2xl leading-snug text-ink sm:text-3xl">{rec.title}</h3>
            <EvidenceLinks findings={rec.findings} />
          </div>
          <span className="rounded-full border border-line px-3 py-1 text-xs text-muted">
            {ui.effort}: <span className="text-ink">{d.effort}</span>
          </span>
        </header>

        <dl className="grid gap-6 md:grid-cols-2">
          <Field label={ui.change}>{d.change}</Field>

          <Field label={ui.evidence}>
            <ul className="space-y-1.5">
              {Object.entries(rec.evidence).map(([id, n]) => (
                <li key={id} className="flex items-baseline justify-between gap-4">
                  <span className="text-ink/80">{n.label}</span>
                  <span className="shrink-0 font-mono tabular-nums text-accent">{n.display}</span>
                </li>
              ))}
            </ul>
          </Field>

          <Field label={ui.target_metric}>
            {d.target_metric}{" "}
            <span className="whitespace-nowrap text-muted">
              ({ui.expected_direction.toLowerCase()}: <span className="text-accent">{d.expected_direction}</span>)
            </span>
          </Field>

          <Field label={ui.risk}>{d.risk}</Field>

          <Field label={ui.test_design} className="md:col-span-2">
              <dl className="grid gap-x-6 gap-y-2 sm:grid-cols-[auto_1fr]">
                {d.test_design.map((t) => (
                  <div key={t.label} className="contents">
                    <dt className="text-muted">{t.label}</dt>
                    <dd className="text-ink/90">{t.text}</dd>
                  </div>
                ))}
              </dl>
          </Field>
        </dl>
      </article>
    </GlassCard>
  );
}
