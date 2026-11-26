// Data model: the 9 raw tables and the clean views built on them
// (site/data/schema.json). Columns are build depth: raw tables, then views
// built from tables, then views built from views. Hovering or focusing a box
// highlights its joins and shows its key columns and row count below.
// On phones the same information is a plain list.
import { useMemo, useState } from "react";
import schemaJson from "../../../data/schema.json";
import { site } from "../../data/data";
import type { SchemaFile } from "../../data/types";
import { useMediaQuery } from "../../hooks/useMediaQuery";
import { useWidth } from "../../hooks/useWidth";

const schema = schemaJson as unknown as SchemaFile;
const fmt = (n: number) => n.toLocaleString("en-US");

interface Node {
  name: string;
  kind: "table" | "view";
  depth: number;
  rows: number;
  keys: string[]; // primary key columns
  joins: string[]; // join keys, both directions: "customer_id → customers.customer_id"
  grain?: string;
  builtFrom: string[];
  usedBy: string[];
}

interface Edge {
  from: string;
  to: string;
  kind: "foreign key" | "built from";
}

/** Nodes, edges and the column each node sits in, from schema.json. */
function buildModel() {
  const nodes = new Map<string, Node>();
  for (const t of schema.tables)
    nodes.set(t.name, { name: t.name, kind: "table", depth: 0, rows: t.row_count, keys: t.primary_key, joins: [], builtFrom: [], usedBy: [] });
  for (const v of schema.views)
    nodes.set(v.name, { name: v.name, kind: "view", depth: 0, rows: v.row_count, keys: [], joins: [], grain: v.grain, builtFrom: v.built_from, usedBy: [] });

  const edges: Edge[] = schema.relationships.map((r) => ({
    from: r.from.split(".")[0],
    to: r.to.split(".")[0],
    kind: r.kind,
  }));
  for (const r of schema.relationships) {
    if (r.kind === "foreign key") {
      nodes.get(r.from.split(".")[0])?.joins.push(`${r.from.split(".")[1]} → ${r.to}`);
      nodes.get(r.to.split(".")[0])?.joins.push(`${r.to.split(".")[1]} ← ${r.from}`);
    } else nodes.get(r.to)?.usedBy.push(r.from);
  }
  // depth of a view = 1 + deepest source
  const depthOf = (n: string, seen = new Set<string>()): number => {
    const node = nodes.get(n);
    if (!node || node.kind === "table" || seen.has(n)) return 0;
    seen.add(n);
    return 1 + Math.max(0, ...node.builtFrom.map((s) => depthOf(s, seen)));
  };
  for (const n of nodes.values()) n.depth = depthOf(n.name);

  // Columns, ordered to reduce crossings: sort each column by the average
  // position of its neighbours, sweeping right then left a few times.
  const maxDepth = Math.max(...[...nodes.values()].map((n) => n.depth));
  const cols: string[][] = Array.from({ length: maxDepth + 1 }, (_, d) =>
    [...nodes.values()].filter((n) => n.depth === d).map((n) => n.name),
  );
  const built = edges.filter((e) => e.kind === "built from");
  const pos = () => new Map(cols.flatMap((c) => c.map((n, i) => [n, i / Math.max(1, c.length - 1)] as const)));
  for (let pass = 0; pass < 4; pass++) {
    const order = pass % 2 === 0 ? cols.map((_, i) => i).slice(1) : cols.map((_, i) => i).slice(0, -1).reverse();
    for (const d of order) {
      const p = pos();
      const score = (n: string) => {
        const nb = built.filter((e) => e.from === n || e.to === n).map((e) => (e.from === n ? e.to : e.from));
        const vals = nb.map((x) => p.get(x)).filter((v): v is number => v !== undefined);
        return vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : (p.get(n) ?? 0);
      };
      cols[d].sort((a, b) => score(a) - score(b));
    }
  }
  return { nodes, edges, cols };
}

export function DataModel() {
  const wide = useMediaQuery("(min-width: 768px)");
  const model = useMemo(buildModel, []);
  return wide ? <Diagram model={model} /> : <ModelList model={model} />;
}

// ---------------------------------------------------------------- diagram
const CHAR_W = 7.3; // JetBrains Mono at 12px
const LINE_H = 16;
const PAD_X = 10;
const NODE_GAP = 10;
const ARC_ROOM = 44; // left margin for the join arcs between raw tables

/** Break a snake_case name onto lines that fit, at underscores. */
function wrapName(name: string, maxChars: number) {
  const parts = name.split(/(?<=_)/);
  const lines: string[] = [];
  let cur = "";
  for (const p of parts) {
    if (cur && (cur + p).length > maxChars) {
      lines.push(cur);
      cur = p;
    } else cur += p;
  }
  if (cur) lines.push(cur);
  return lines;
}

function Diagram({ model }: { model: ReturnType<typeof buildModel> }) {
  const copy = site.under_the_hood.model;
  const { nodes, edges, cols } = model;
  const [box, width] = useWidth<HTMLDivElement>();
  const [active, setActive] = useState<string | null>(null);

  const colGap = 44;
  const colW = Math.max(120, (width - ARC_ROOM - colGap * (cols.length - 1)) / cols.length);
  const maxChars = Math.floor((colW - PAD_X * 2) / CHAR_W);

  // Node boxes: name lines + a row-count line.
  const layout = new Map<string, { x: number; y: number; w: number; h: number; lines: string[] }>();
  const colHeights = cols.map((c) =>
    c.reduce((h, n) => h + (wrapName(n, maxChars).length + 1) * LINE_H + 14 + NODE_GAP, -NODE_GAP),
  );
  const height = Math.max(...colHeights) + 4;
  cols.forEach((c, d) => {
    let y = (height - colHeights[d]) / 2;
    for (const n of c) {
      const lines = wrapName(n, maxChars);
      const h = (lines.length + 1) * LINE_H + 14;
      layout.set(n, { x: ARC_ROOM + d * (colW + colGap), y, w: colW, h, lines });
      y += h + NODE_GAP;
    }
  });

  const linked = (e: Edge) => active !== null && (e.from === active || e.to === active);
  const neighbours = new Set(edges.filter(linked).flatMap((e) => [e.from, e.to]));
  const fkEdges = edges.filter((e) => e.kind === "foreign key");
  const node = active ? nodes.get(active) : null;

  return (
    <div>
      <ul className="mb-4 flex flex-wrap gap-x-5 gap-y-2 text-xs text-muted">
        <li className="flex items-center gap-2">
          <span aria-hidden="true" className="h-3 w-4 rounded-[3px] border border-line-strong bg-card" />
          {copy.raw_table}
        </li>
        <li className="flex items-center gap-2">
          <span aria-hidden="true" className="h-3 w-4 rounded-[3px] border border-accent/60 bg-accent/10" />
          {copy.clean_view}
        </li>
        <li className="flex items-center gap-2">
          <span aria-hidden="true" className="h-0.5 w-4 rounded-full bg-slate-text" />
          {copy.foreign_key}
        </li>
        <li className="flex items-center gap-2">
          <span aria-hidden="true" className="h-0.5 w-4 rounded-full bg-accent/70" />
          {copy.built_from}
        </li>
      </ul>
      <div ref={box} onPointerLeave={() => setActive(null)}>
        {width > 0 && (
          <svg width={width} height={height} className="block" role="group" aria-label={site.under_the_hood.panels.find((p) => p.id === "model")?.title}>
            {/* built-from edges: source right edge -> target left edge */}
            {edges
              .filter((e) => e.kind === "built from")
              .map((e) => {
                const a = layout.get(e.to); // source (view is built from e.to)
                const b = layout.get(e.from);
                if (!a || !b) return null;
                const x1 = a.x + a.w, y1 = a.y + a.h / 2, x2 = b.x, y2 = b.y + b.h / 2;
                const mx = (x1 + x2) / 2;
                const on = linked(e);
                return (
                  <path
                    key={`${e.from}-${e.to}`}
                    d={`M${x1},${y1}C${mx},${y1} ${mx},${y2} ${x2},${y2}`}
                    fill="none"
                    className={`transition-opacity ${on ? "stroke-accent" : "stroke-accent/35"}`}
                    strokeWidth={on ? 2 : 1}
                    opacity={active && !on ? 0.25 : 1}
                  />
                );
              })}
            {/* join keys between raw tables: arcs on the left */}
            {fkEdges.map((e, i) => {
              const a = layout.get(e.from);
              const b = layout.get(e.to);
              if (!a || !b) return null;
              const y1 = a.y + a.h / 2, y2 = b.y + b.h / 2;
              // control points at most 52px left: the curve stays inside ARC_ROOM
              const bulge = 8 + (i % 4) * 6;
              const on = linked(e);
              return (
                <path
                  key={`fk-${e.from}-${e.to}`}
                  d={`M${a.x},${y1}C${a.x - bulge * 2},${y1} ${b.x - bulge * 2},${y2} ${b.x},${y2}`}
                  fill="none"
                  className={`transition-opacity ${on ? "stroke-ink" : "stroke-slate-text/60"}`}
                  strokeWidth={on ? 2 : 1}
                  opacity={active && !on ? 0.25 : 1}
                />
              );
            })}
            {[...layout.entries()].map(([name, l]) => {
              const n = nodes.get(name)!;
              const dim = active !== null && !neighbours.has(name) && active !== name;
              const isActive = active === name;
              return (
                <g
                  key={name}
                  tabIndex={0}
                  role="button"
                  aria-label={`${name}, ${n.kind === "table" ? copy.raw_table : copy.clean_view}, ${fmt(n.rows)} ${copy.rows}`}
                  aria-describedby="model-detail"
                  onPointerEnter={() => setActive(name)}
                  onFocus={() => setActive(name)}
                  onBlur={() => setActive(null)}
                  className="cursor-default outline-none"
                  opacity={dim ? 0.35 : 1}
                >
                  <rect
                    x={l.x}
                    y={l.y}
                    width={l.w}
                    height={l.h}
                    rx={8}
                    // opaque fills, so edges passing behind a box never show through it
                    className={
                      n.kind === "table"
                        ? `fill-card ${isActive ? "stroke-ink" : "stroke-line-strong"}`
                        : isActive ? "stroke-accent" : "stroke-accent/50"
                    }
                    style={n.kind === "view" ? { fill: "color-mix(in srgb, var(--color-accent) 10%, var(--color-card))" } : undefined}
                    strokeWidth={isActive ? 2 : 1}
                  />
                  <text x={l.x + PAD_X} y={l.y + 7 + LINE_H * 0.75} className="fill-ink font-mono text-[12px]">
                    {l.lines.map((line, k) => (
                      <tspan key={k} x={l.x + PAD_X} dy={k === 0 ? 0 : LINE_H}>
                        {line}
                      </tspan>
                    ))}
                  </text>
                  <text
                    x={l.x + PAD_X}
                    y={l.y + 7 + LINE_H * (l.lines.length + 0.75)}
                    className="fill-muted text-[12px] tabular-nums"
                  >
                    {fmt(n.rows)} {copy.rows}
                  </text>
                </g>
              );
            })}
          </svg>
        )}
      </div>
      <Detail node={node ?? null} />
    </div>
  );
}

/** Key columns, joins and row count of the hovered box (live region). */
function Detail({ node }: { node: Node | null }) {
  const copy = site.under_the_hood.model;
  return (
    <div id="model-detail" aria-live="polite" className="mt-4 min-h-[7.5rem] rounded-xl border border-line p-4 text-sm">
      {!node ? (
        <p className="text-muted">{copy.hint}</p>
      ) : (
        <>
        <p className="mb-2 font-mono text-accent">
          {node.name}{" "}
          <span className="font-sans text-muted">
            · {node.kind === "table" ? copy.raw_table : copy.clean_view} · {fmt(node.rows)} {copy.rows}
          </span>
        </p>
        <dl className="grid gap-x-6 gap-y-2 sm:grid-cols-[8rem_1fr]">
          {node.kind === "table" ? (
            <>
              <dt className="text-muted">{copy.key_columns}</dt>
              <dd className="font-mono text-ink">{node.keys.length ? node.keys.join(", ") : "–"}</dd>
              {node.joins.length > 0 && (
                <>
                  <dt className="text-muted">{copy.joins}</dt>
                  <dd className="font-mono text-ink">{node.joins.join(" · ")}</dd>
                </>
              )}
              {node.usedBy.length > 0 && (
                <>
                  <dt className="text-muted">{copy.used_by}</dt>
                  <dd className="font-mono text-ink">{node.usedBy.join(" · ")}</dd>
                </>
              )}
            </>
          ) : (
            <>
              <dt className="text-muted">{copy.grain}</dt>
              <dd className="text-ink">{node.grain}</dd>
              <dt className="text-muted">{copy.built_from}</dt>
              <dd className="font-mono text-ink">{node.builtFrom.join(" · ")}</dd>
            </>
          )}
        </dl>
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------- phones
function ModelList({ model }: { model: ReturnType<typeof buildModel> }) {
  const copy = site.under_the_hood.model;
  const all = [...model.nodes.values()];
  const group = (kind: Node["kind"]) => all.filter((n) => n.kind === kind);
  return (
    <div className="space-y-8">
      {(["table", "view"] as const).map((kind) => (
        <div key={kind}>
          <h4 className="mb-3 text-xs font-medium uppercase tracking-[0.18em] text-muted">
            {kind === "table" ? copy.tables_heading : copy.views_heading}
          </h4>
          <ul className="divide-y divide-line rounded-xl border border-line">
            {group(kind).map((n) => (
              <li key={n.name} className="px-4 py-3 text-sm">
                <p className="flex flex-wrap items-baseline justify-between gap-x-3">
                  <span className="font-mono break-all text-ink">{n.name}</span>
                  <span className="text-xs text-muted tabular-nums">
                    {fmt(n.rows)} {copy.rows}
                  </span>
                </p>
                {kind === "table" ? (
                  <dl className="mt-1 space-y-1 text-xs text-muted">
                    <div>
                      <dt className="inline">{copy.key_columns}: </dt>
                      <dd className="inline font-mono text-ink/90">{n.keys.length ? n.keys.join(", ") : "–"}</dd>
                    </div>
                    {n.joins.length > 0 && (
                      <div>
                        <dt>{copy.joins}:</dt>
                        {/* one join per line, so long keys never break mid-name */}
                        {n.joins.map((j) => (
                          <dd key={j} className="font-mono text-ink/90">
                            {j}
                          </dd>
                        ))}
                      </div>
                    )}
                  </dl>
                ) : (
                  <>
                  <p className="mt-1 text-xs text-muted">{n.grain}</p>
                  <dl className="mt-1 text-xs text-muted">
                    <div>
                      <dt className="inline">{copy.built_from}: </dt>
                      <dd className="inline font-mono text-ink/90">{n.builtFrom.join(", ")}</dd>
                    </div>
                  </dl>
                  </>
                )}
              </li>
            ))}
          </ul>
        </div>
      ))}
    </div>
  );
}
