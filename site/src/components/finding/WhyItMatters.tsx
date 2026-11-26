// The chapter's closing line, linking to the recommendation it supports.
import { recommendationById, site } from "../../data/data";
import type { ChapterCopy } from "../../data/types";
import { useScrollTo } from "../../hooks/SmoothScroll";

export function WhyItMatters({ chapter }: { chapter: ChapterCopy }) {
  const rec = recommendationById[chapter.recommendation];
  const scrollTo = useScrollTo();

  return (
    <aside className="mt-10 border-l-2 border-accent/60 pl-5">
      <p className="mb-2 text-xs font-medium uppercase tracking-[0.22em] text-accent">{site.ui.why_it_matters}</p>
      <p className="text-lg leading-relaxed text-ink">{chapter.why.text}</p>
      <a
        href={`#rec-${rec.id}`}
        onClick={(e) => {
          e.preventDefault();
          scrollTo(`rec-${rec.id}`);
        }}
        className="group mt-5 block max-w-2xl"
      >
        <span className="block text-xs uppercase tracking-[0.18em] text-muted">
          {site.ui.see_recommendation} · <span className="font-mono text-accent">{rec.id}</span>
        </span>
        <span className="mt-1 block text-sm leading-relaxed text-ink/85 transition-colors group-hover:text-accent">
          {rec.title} <span aria-hidden="true">→</span>
        </span>
      </a>
    </aside>
  );
}
