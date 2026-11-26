// "View SQL": the key query for the finding, highlighted with Shiki, its
// annotated lines, and the first rows of its result. queries.json and Shiki
// are both loaded on first open only.
import { useEffect, useState } from "react";
import { loadQueries, site } from "../../data/data";
import type { QueryEntry } from "../../data/types";

export function SqlPanel({ findingId }: { findingId: string }) {
  const [entry, setEntry] = useState<QueryEntry | null>(null);
  const [html, setHtml] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { queries } = await loadQueries();
      const q = queries.find((x) => x.finding === findingId) ?? null;
      if (cancelled || !q) return;
      setEntry(q);
      const { highlightSql } = await import("../../lib/highlighter");
      const out = await highlightSql(q.sql, q.annotations.map((a) => a.line_number));
      if (!cancelled) setHtml(out);
    })();
    return () => {
      cancelled = true;
    };
  }, [findingId]);

  if (!entry) return <p className="text-sm text-muted">{site.ui.loading}…</p>;

  return (
    <div className="space-y-6">
      <p className="text-sm text-muted">
        <span className="font-mono text-ink">{entry.file}</span> · {entry.title}
      </p>

      <div className="glass overflow-x-auto py-4" data-lenis-prevent>
        {html ? (
          <div className="sql-code" dangerouslySetInnerHTML={{ __html: html }} />
        ) : (
          <pre className="px-4 font-mono text-xs text-muted">{entry.sql}</pre>
        )}
      </div>

      <ol className="space-y-3">
        {entry.annotations.map((a) => (
          <li key={a.line_number} className="grid grid-cols-[auto_1fr] gap-x-3 text-sm">
            <span className="mt-0.5 rounded bg-accent-soft px-1.5 font-mono text-xs text-accent">L{a.line_number}</span>
            <span className="leading-relaxed text-ink/90">{a.note}</span>
          </li>
        ))}
      </ol>

      <ResultPreview entry={entry} />
    </div>
  );
}

function ResultPreview({ entry }: { entry: QueryEntry }) {
  const { columns, rows, file } = entry.result;
  return (
    <div>
      <p className="mb-2 text-xs uppercase tracking-[0.18em] text-muted">{site.ui.result_preview}</p>
      <div className="overflow-x-auto rounded-lg border border-line" data-lenis-prevent>
        <table className="w-full min-w-max border-collapse text-left font-mono text-xs">
          <thead>
            <tr className="bg-card">
              {columns.map((c) => (
                <th key={c} scope="col" className="border-b border-line px-3 py-2 font-medium text-muted">
                  {c}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((r, i) => (
              <tr key={i} className="border-b border-line/60 last:border-0">
                {columns.map((c) => {
                  const v = r[c] === null ? "" : String(r[c]);
                  const numeric = /^-?[\d.]+$/.test(v); // right-align numbers, shown verbatim
                  return (
                    <td key={c} className={`px-3 py-2 tabular-nums ${numeric ? "text-right text-ink" : "text-ink/80"}`}>
                      {v}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="mt-2 text-xs text-muted">
        {site.ui.source}: <span className="font-mono">{file}</span>
      </p>
    </div>
  );
}
