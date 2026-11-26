// Slim fixed top bar: project title (jumps to top) and the GitHub button.
import { site } from "../../data/data";
import { useScrollTo } from "../../hooks/SmoothScroll";
import { MobileProgress } from "./MobileProgress";

export function TopBar() {
  const scrollTo = useScrollTo();
  const { github } = site.links;

  return (
    <header className="fixed inset-x-0 top-0 z-40 border-b border-line/80 bg-bg/80 backdrop-blur-md">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
        <button
          type="button"
          onClick={() => scrollTo("top")}
          className="truncate font-serif text-lg text-ink transition-colors hover:text-accent"
        >
          {site.meta.nav_title}
        </button>
        <GitHubButton href={github} label={site.ui.view_on_github} />
      </div>
      <MobileProgress />
    </header>
  );
}

// The repo URL lives in one place: links.github in docs/site_copy.json.
function GitHubButton({ href, label }: { href: string; label: string }) {
  const classes =
    "inline-flex shrink-0 items-center gap-2 rounded-full border border-line px-3.5 py-1.5 text-xs font-medium text-ink transition-colors";
  const icon = (
    <svg aria-hidden="true" viewBox="0 0 16 16" className="h-3.5 w-3.5 fill-current">
      <path d="M8 0C3.58 0 0 3.58 0 8a8 8 0 0 0 5.47 7.59c.4.07.55-.17.55-.38v-1.33c-2.23.48-2.7-1.07-2.7-1.07-.36-.92-.89-1.17-.89-1.17-.73-.5.06-.49.06-.49.8.06 1.23.83 1.23.83.72 1.22 1.87.87 2.33.66.07-.52.28-.87.5-1.07-1.78-.2-3.65-.89-3.65-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.6 7.6 0 0 1 4 0c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48v2.2c0 .21.15.46.55.38A8 8 0 0 0 16 8c0-4.42-3.58-8-8-8Z" />
    </svg>
  );
  return (
    <a href={href} target="_blank" rel="noreferrer" className={`${classes} hover:border-accent hover:text-accent`}>
      {icon}
      {label}
    </a>
  );
}
