// Under the hood, lazily loaded with schema.json, quality.json and
// techniques.json: the data model, a card per data-quality decision, and a
// card per SQL technique with a jump to the chapter whose SQL shows it.
import qualityJson from "../../../data/quality.json";
import techniquesJson from "../../../data/techniques.json";
import { site } from "../../data/data";
import { chapterNumber } from "../../data/sections";
import type { QualityFile, TechniquesFile } from "../../data/types";
import { useScrollTo } from "../../hooks/SmoothScroll";
import { openPanel } from "../ui/Disclosure";
import { DataModel } from "./DataModel";

const quality = qualityJson as unknown as QualityFile;
const techniques = techniquesJson as unknown as TechniquesFile;
const fmt = (n: number) => n.toLocaleString("en-US");

export default function HoodContent() {
  const h = site.under_the_hood;
  const panel = (id: string) => h.panels.find((p) => p.id === id);
  const body: Record<string, () => React.ReactNode> = {
    model: () => <DataModel />,
    quality: () => <QualityCards />,
    techniques: () => <TechniqueCards />,
  };
  return (
    <div className="space-y-20">
      {(["model", "quality", "techniques"] as const).map((id) => {
        const p = panel(id);
        if (!p) return null;
        return (
          <section key={id} aria-labelledby={`hood-${id}`}>
            <h3 id={`hood-${id}`} className="font-serif text-3xl text-ink">
              {p.title}
            </h3>
            <p className="mt-2 mb-6 max-w-2xl text-sm leading-relaxed text-muted">{p.text}</p>
            {body[id]()}
          </section>
        );
      })}
    </div>
  );
}

function QualityCards() {
  const q = site.under_the_hood.quality;
  return (
    <ul className="grid gap-4 md:grid-cols-2">
      {quality.issues.map((issue) => (
        <li key={issue.id} className="glass flex flex-col p-5">
          <p className="text-xs font-medium uppercase tracking-[0.18em] text-muted">{q.problem}</p>
          <p className="mt-2 text-sm leading-relaxed text-ink">{issue.issue}</p>
          <p className="mt-4 flex flex-wrap items-baseline gap-x-2">
            <span className="text-3xl font-semibold text-accent">{fmt(issue.affected)}</span>
            <span className="text-sm text-muted">{issue.unit}</span>
          </p>
          <div className="mt-4 border-t border-line pt-4">
            <p className="text-xs font-medium uppercase tracking-[0.18em] text-muted">{q.decision}</p>
            <p className="mt-2 text-sm leading-relaxed text-ink/90">{issue.decision}</p>
          </div>
          <p className="mt-auto pt-4 text-xs text-muted">
            {q.ref}: <span className="font-mono text-ink/80">{issue.decision_ref}</span>
          </p>
        </li>
      ))}
    </ul>
  );
}

function TechniqueCards() {
  const t = site.under_the_hood.techniques;
  const scrollTo = useScrollTo();
  const chapterIndex = Object.fromEntries(site.chapters.map((c, i) => [c.id, i]));
  const linkClass =
    "inline-flex min-h-11 items-center gap-2 rounded-full border border-line px-4 text-sm text-ink transition-colors hover:border-accent hover:text-accent";

  return (
    <ul className="grid gap-4 sm:grid-cols-2">
      {techniques.techniques.map((tech) => {
        const target = tech.chapters[0];
        return (
          <li key={tech.technique} className="glass flex flex-col p-5">
            <h4 className="font-mono text-base text-accent">{tech.technique}</h4>
            <p className="mt-2 text-sm leading-relaxed text-ink/90">{tech.description}</p>
            <p className="mt-4 text-xs text-muted">{t.used_in}</p>
            <ul className="mt-1 space-y-1 text-xs">
              {tech.uses.slice(0, 3).map((u) => (
                <li key={`${u.file}-${u.section}`} className="text-ink/80">
                  <span className="font-mono">{u.file.replace(/^sql\//, "")}</span>
                  <span className="text-muted"> · {u.section}</span>
                </li>
              ))}
            </ul>
            <div className="mt-auto pt-5">
              {target ? (
                <button
                  type="button"
                  className={linkClass}
                  onClick={() => {
                    openPanel(`sql-${target}`);
                    requestAnimationFrame(() => scrollTo(`sql-${target}`));
                  }}
                >
                  {t.see_it_used}
                  <span className="text-muted">
                    · {t.chapter} {chapterNumber(chapterIndex[target])}
                  </span>
                  <span aria-hidden="true">→</span>
                </button>
              ) : (
                <a
                  className={linkClass}
                  href={`${site.links.github_file_base}${tech.uses[0].file}`}
                  target="_blank"
                  rel="noreferrer"
                  aria-label={`${t.view_file}: ${tech.uses[0].file}`}
                >
                  {/* the file is named under "Used in"; the label stays on one line */}
                  <span className="whitespace-nowrap">{t.view_file}</span>
                  <span aria-hidden="true">↗</span>
                </a>
              )}
            </div>
          </li>
        );
      })}
    </ul>
  );
}
