// Footer: repo and case-study links, then credits: the dataset (with its
// licence), the state boundaries, and the author.
import { site } from "../../data/data";

const linkClass = "text-ink underline decoration-line underline-offset-4 transition-colors hover:text-accent hover:decoration-accent";

export function Footer() {
  const { links, footer, ui } = site;
  return (
    <footer className="mt-32 border-t border-line">
      <div className="mx-auto flex max-w-4xl flex-col gap-6 px-4 py-12 text-sm text-muted sm:px-6 md:flex-row md:items-center md:justify-between">
        <nav className="flex flex-wrap gap-x-6 gap-y-2">
          <a href={links.github} target="_blank" rel="noreferrer" className={linkClass}>
            {ui.view_on_github}
          </a>
          <a href={links.case_study_pdf} target="_blank" rel="noreferrer" className={linkClass}>
            {ui.case_study_pdf}
          </a>
        </nav>
        <section aria-labelledby="credits-title" className="flex flex-col gap-1.5 md:items-end md:text-right">
          <h2 id="credits-title" className="mb-1 text-xs font-medium uppercase tracking-[0.18em] text-muted">
            {footer.credits_label}
          </h2>
          {/* one link per line, each tall enough to tap */}
          <ul className="flex flex-col gap-1 md:items-end">
            {[
              { href: links.dataset, text: footer.dataset_credit, rel: "noreferrer" },
              { href: links.dataset_license, text: footer.dataset_license, rel: "noreferrer license" },
              { href: links.geo, text: footer.geo_credit, rel: "noreferrer" },
              { href: links.author, text: footer.built_by, rel: "noreferrer" },
            ].map((l) => (
              <li key={l.href}>
                <a href={l.href} target="_blank" rel={l.rel} className={`${linkClass} inline-block py-1`}>
                  {l.text}
                </a>
              </li>
            ))}
          </ul>
        </section>
      </div>
    </footer>
  );
}
