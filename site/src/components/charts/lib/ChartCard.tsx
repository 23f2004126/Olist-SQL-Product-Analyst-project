// The frame every chart sits in: a one-line finding as the title, a subtitle
// saying what is plotted, an optional legend, the chart, and a "View data"
// toggle that shows the same numbers as a table (also the accessible
// fallback: the chart itself is one labelled image).
import { useId, useState, type ReactNode } from "react";
import { charts } from "../../../data/charts";

export interface TableSpec {
  columns: { label: string; numeric?: boolean }[];
  rows: (string | number)[][];
  note?: string;
}

interface Props {
  chartId: string;
  legend?: ReactNode;
  table: TableSpec;
  children: ReactNode;
}

export function ChartCard({ chartId, legend, table, children }: Props) {
  const copy = charts.items[chartId];
  const ui = charts.ui;
  const [open, setOpen] = useState(false);
  const id = useId();
  const titleId = `${id}-title`;
  const subId = `${id}-sub`;
  const tableId = `${id}-table`;

  return (
    <figure className="glass m-0 flex h-full min-w-0 flex-col p-4 sm:p-6" aria-labelledby={titleId}>
      <h3 id={titleId} className="font-serif text-xl leading-snug text-ink sm:text-[1.4rem]">
        {copy.title.text}
      </h3>
      <p id={subId} className="mt-2 text-sm leading-relaxed text-muted">
        {copy.subtitle.text}
      </p>
      {legend && <div className="mt-4">{legend}</div>}

      {/* The drawing is one image for assistive tech; its numbers are in the table. */}
      <div role="img" aria-labelledby={titleId} aria-describedby={subId} className="relative mt-5 min-w-0 flex-1">
        {children}
      </div>

      <div className="mt-4 border-t border-line pt-3">
        <button
          type="button"
          aria-expanded={open}
          aria-controls={open ? tableId : undefined}
          onClick={() => setOpen((o) => !o)}
          className="inline-flex min-h-11 items-center gap-2 rounded-full px-1 text-sm text-muted transition-colors hover:text-accent"
        >
          <span aria-hidden="true" className={`inline-block transition-transform ${open ? "rotate-90" : ""}`}>
            ›
          </span>
          {open ? ui.hide_data : ui.view_data}
        </button>
        {open && <DataTable id={tableId} caption={`${ui.data_table}: ${copy.title.text}`} spec={table} />}
      </div>
    </figure>
  );
}

function DataTable({ id, caption, spec }: { id: string; caption: string; spec: TableSpec }) {
  return (
    <div id={id} className="mt-2">
      {/* Wide tables scroll inside their own box, never the page. */}
      <div className="max-h-96 overflow-auto rounded-lg border border-line" tabIndex={0} role="region" aria-label={caption}>
        <table className="w-full border-collapse text-left text-xs">
          <caption className="sr-only">{caption}</caption>
          <thead className="sticky top-0 bg-card">
            <tr>
              {spec.columns.map((c) => (
                <th
                  key={c.label}
                  scope="col"
                  className={`border-b border-line px-3 py-2 font-medium whitespace-nowrap text-muted ${c.numeric ? "text-right" : ""}`}
                >
                  {c.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {spec.rows.map((r, i) => (
              <tr key={i} className="border-b border-line/60 last:border-0">
                {r.map((cell, j) =>
                  j === 0 ? (
                    <th key={j} scope="row" className="px-3 py-1.5 font-normal whitespace-nowrap text-ink">
                      {cell}
                    </th>
                  ) : (
                    <td
                      key={j}
                      className={`px-3 py-1.5 whitespace-nowrap text-ink ${spec.columns[j]?.numeric ? "text-right font-mono tabular-nums" : ""}`}
                    >
                      {cell}
                    </td>
                  ),
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {spec.note && <p className="mt-2 text-xs text-muted">{spec.note}</p>}
    </div>
  );
}

/** Legend row: a swatch (rect for bars/areas, dot for dots, line for lines) and its label. */
export function Legend({ items }: { items: { label: string; swatch: ReactNode }[] }) {
  return (
    <ul className="flex flex-wrap gap-x-5 gap-y-2 text-xs text-muted">
      {items.map((it) => (
        <li key={it.label} className="flex items-center gap-2">
          <span aria-hidden="true" className="inline-flex">
            {it.swatch}
          </span>
          {it.label}
        </li>
      ))}
    </ul>
  );
}

export const Swatch = ({ className, shape = "rect" }: { className: string; shape?: "rect" | "dot" | "line" | "outline" }) =>
  shape === "dot" ? (
    <span className={`h-2.5 w-2.5 rounded-full ${className}`} />
  ) : shape === "line" ? (
    <span className={`h-0.5 w-4 rounded-full ${className}`} />
  ) : shape === "outline" ? (
    <span className={`h-3 w-3 rounded-[3px] border ${className}`} />
  ) : (
    <span className={`h-3 w-3 rounded-[3px] ${className}`} />
  );
