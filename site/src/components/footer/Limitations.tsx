// Section 9: limitations from findings.json.
import { findingsFile, site } from "../../data/data";
import { Section } from "../layout/Section";

export function Limitations() {
  return (
    <Section id="limitations" label={site.limitations.label} title={site.limitations.title}>
      <ol className="grid gap-x-10 gap-y-5 md:grid-cols-2">
        {findingsFile.limitations.map((l, i) => (
          <li key={l.id} className="grid grid-cols-[auto_1fr] gap-x-4 border-t border-line pt-4">
            <span className="font-mono text-xs text-muted">{String(i + 1).padStart(2, "0")}</span>
            <p className="text-sm leading-relaxed text-ink/85">{l.text}</p>
          </li>
        ))}
      </ol>
    </Section>
  );
}
