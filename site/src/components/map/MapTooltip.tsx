// Tooltip for the hovered state: name, delivered orders, late rate and
// median delivery days, all from map.json (results/15_state_delivery.csv).
import { site } from "../../data/data";
import type { MapMetaFile } from "../../data/types";

export interface HoverInfo {
  uf: string;
  x: number; // pointer position inside the map, in CSS pixels
  y: number;
}

const OFFSET = 16;
const WIDTH = 220; // matches w-[220px] below; used to flip near the right edge

export function MapTooltip({
  info,
  name,
  figures,
  containerWidth,
}: {
  info: HoverInfo;
  name: string;
  figures: MapMetaFile["states"][string] | undefined;
  containerWidth: number;
}) {
  if (!figures) return null;
  const t = site.map.tooltip;
  const flip = info.x + OFFSET + WIDTH > containerWidth;
  const rows: [string, string][] = [
    [t.delivered_orders, figures.delivered_orders.display],
    [t.late_rate, figures.late_rate_pct.display],
    [t.median_days, figures.median_delivery_days.display],
  ];
  return (
    <div
      role="tooltip"
      className="glass pointer-events-none absolute w-[220px] px-4 py-3 text-xs"
      style={{ left: flip ? info.x - OFFSET - WIDTH : info.x + OFFSET, top: info.y + OFFSET }}
    >
      <p className="mb-2 font-serif text-base text-ink">
        {name} <span className="font-sans text-xs text-muted">{info.uf}</span>
      </p>
      <dl className="space-y-1">
        {rows.map(([label, value]) => (
          <div key={label} className="flex justify-between gap-3">
            <dt className="text-muted">{label}</dt>
            <dd className="font-mono tabular-nums text-accent">{value}</dd>
          </div>
        ))}
      </dl>
    </div>
  );
}
