// One finding chapter (F1-F5): PM story first (headline, key numbers, chart),
// then the evidence one click below (pipeline, SQL), then why it matters.
import { useEffect } from "react";
import { findingById, loadPipelines, site } from "../../data/data";
import { chapterNumber } from "../../data/sections";
import type { ChapterCopy } from "../../data/types";
import { Section } from "../layout/Section";
import { Disclosure } from "../ui/Disclosure";
import { ChartsSlot } from "./ChartsSlot";
import { KeyNumbers } from "./KeyNumbers";
import { PipelinePanel } from "./PipelinePanel";
import { SqlPanel } from "./SqlPanel";
import { WhyItMatters } from "./WhyItMatters";

export function FindingChapter({ chapter, index }: { chapter: ChapterCopy; index: number }) {
  const finding = findingById[chapter.id];
  const label = `${site.ui.chapter} ${chapterNumber(index)}`;

  // Fetch the funnels at idle time so "How we got this" opens instantly.
  useEffect(() => {
    const idle = window.requestIdleCallback ?? ((cb: () => void) => window.setTimeout(cb, 1500));
    idle(() => void loadPipelines());
  }, []);

  return (
    <Section id={`chapter-${chapter.id}`} label={label} title={chapter.title}>
      <p className="max-w-3xl font-serif text-2xl leading-snug text-ink/90 sm:text-[1.75rem]">
        {finding.headline}
      </p>

      <KeyNumbers finding={finding} cardIds={chapter.cards} />

      <div className="mt-8">
        <ChartsSlot chartIds={chapter.charts} />
      </div>

      <div className="mt-8">
        <Disclosure label={site.ui.how_we_got_this}>
          <PipelinePanel findingId={chapter.id} />
        </Disclosure>
        <Disclosure id={`sql-${chapter.id}`} label={site.ui.view_sql}>
          <SqlPanel findingId={chapter.id} />
        </Disclosure>
      </div>

      <WhyItMatters chapter={chapter} />
    </Section>
  );
}
