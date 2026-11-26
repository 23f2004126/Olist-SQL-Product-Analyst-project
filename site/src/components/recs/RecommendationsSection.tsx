// Section 7: impact against effort for the three recommendations, then one
// card each.
import { findingsFile, site } from "../../data/data";
import { Section } from "../layout/Section";
import { ImpactMatrix } from "./ImpactMatrix";
import { RecommendationCard } from "./RecommendationCard";

export function RecommendationsSection() {
  const r = site.recommendations;
  return (
    <Section id="recommendations" label={r.label} title={r.title}>
      <p className="mb-10 max-w-2xl text-lg text-muted">{r.intro}</p>
      <div className="mb-10">
        <ImpactMatrix />
      </div>
      <ol className="space-y-6">
        {findingsFile.recommendations.map((rec) => (
          // the anchor sits on the card's outer edge, so a jump shows the whole card
          <li key={rec.id} id={`rec-${rec.id}`}>
            <RecommendationCard rec={rec} />
          </li>
        ))}
      </ol>
    </Section>
  );
}
