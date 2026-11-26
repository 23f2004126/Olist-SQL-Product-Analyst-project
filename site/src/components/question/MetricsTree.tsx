// Revenue = customers x orders per customer x average order value, with the
// real numbers from kpis.json. Desktop: a root box with SVG connectors to three
// factor boxes. Phones: the same boxes stacked, joined by operator symbols.
import { kpis, site } from "../../data/data";
import type { SourcedNumber } from "../../data/types";
import { CountUp } from "../ui/CountUp";

function TreeNode({ n, root = false }: { n: SourcedNumber; root?: boolean }) {
  return (
    <div
      className={`glass flex flex-col items-center gap-2 px-5 py-5 text-center ${
        root ? "border-accent/40" : ""
      }`}
    >
      <CountUp
        display={n.display}
        className={`font-serif leading-none ${root ? "glow text-4xl text-accent sm:text-5xl" : "text-3xl text-ink"}`}
      />
      <p className="text-sm text-muted">{n.label}</p>
    </div>
  );
}

/** Lines from the root's bottom-centre to the centre of each of 3 equal columns. */
function Connectors() {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 300 48"
      preserveAspectRatio="none"
      className="hidden h-12 w-full sm:block"
    >
      {[50, 150, 250].map((x) => (
        <path
          key={x}
          d={`M150 0 C150 24, ${x} 24, ${x} 48`}
          fill="none"
          stroke="var(--color-line-strong)"
          strokeWidth="1.2"
          vectorEffect="non-scaling-stroke"
        />
      ))}
    </svg>
  );
}

function Operator({ symbol }: { symbol: string }) {
  return (
    <span aria-hidden="true" className="flex items-center justify-center font-serif text-2xl text-muted">
      {symbol}
    </span>
  );
}

export function MetricsTree() {
  const t = kpis.metrics_tree;
  const factors = [t.customers, t.orders_per_customer, t.aov];

  return (
    <figure className="mt-12" aria-label={t.formula}>
      <figcaption className="mb-5 text-xs font-medium uppercase tracking-[0.22em] text-muted">
        {site.question.tree_title}
      </figcaption>

      <div className="mx-auto max-w-sm">
        <TreeNode n={t.revenue} root />
      </div>

      {/* desktop connectors */}
      <Connectors />

      {/* phones: "=" between root and factors */}
      <div className="py-2 sm:hidden">
        <Operator symbol="=" />
      </div>

      <ol className="grid grid-cols-1 gap-2 sm:grid-cols-3 sm:gap-4">
        {factors.map((f, i) => (
          <li key={f.label} className="flex flex-col gap-2">
            {i > 0 && (
              <span className="sm:hidden">
                <Operator symbol="×" />
              </span>
            )}
            <TreeNode n={f} />
          </li>
        ))}
      </ol>

      <p className="mt-4 text-xs text-muted">{t.note}</p>
    </figure>
  );
}
