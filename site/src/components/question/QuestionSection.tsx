// Section 1: the business problem and the metrics tree.
import { site } from "../../data/data";
import { Section } from "../layout/Section";
import { MetricsTree } from "./MetricsTree";

export function QuestionSection() {
  const q = site.question;
  return (
    <Section id="question" label={q.label} title={q.title}>
      <div className="max-w-2xl space-y-4 text-lg leading-relaxed text-ink/90">
        {q.body.map((p) => (
          <p key={p.text_template}>{p.text}</p>
        ))}
      </div>
      <MetricsTree />
    </Section>
  );
}
