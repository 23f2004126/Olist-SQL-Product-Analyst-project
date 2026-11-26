// Map overlay controls: the All / Late only filter and the zoom buttons.
// All labels come from site.json ("map").
import { site } from "../../data/data";

const chip = "rounded-full px-3 py-1.5 text-xs font-medium transition-colors";

export function RouteFilter({ lateOnly, onChange }: { lateOnly: boolean; onChange: (v: boolean) => void }) {
  const m = site.map;
  const options: [boolean, string][] = [
    [false, m.filter_all],
    [true, m.filter_late],
  ];
  return (
    <div
      role="group"
      aria-label={m.filter_label}
      className="glass absolute left-3 top-3 flex gap-1 rounded-full! p-1 sm:left-4 sm:top-4"
    >
      {options.map(([value, label]) => (
        <button
          key={label}
          type="button"
          aria-pressed={lateOnly === value}
          onClick={() => onChange(value)}
          className={`${chip} ${lateOnly === value ? "bg-accent text-bg" : "text-muted hover:text-ink"}`}
        >
          {label}
        </button>
      ))}
    </div>
  );
}

export function ZoomButtons({ onZoom, hint }: { onZoom: (dir: 1 | -1) => void; hint: string }) {
  const m = site.map;
  const btn =
    "glass flex h-9 w-9 items-center justify-center rounded-full! text-lg text-ink transition-colors hover:text-accent";
  return (
    <div className="absolute bottom-4 right-4 flex items-center gap-3">
      <p className="hidden max-w-[16rem] text-right text-[11px] leading-snug text-muted lg:block">{hint}</p>
      <div className="flex flex-col gap-2">
        <button type="button" aria-label={m.zoom_in} title={m.zoom_in} onClick={() => onZoom(1)} className={btn}>
          <span aria-hidden="true">+</span>
        </button>
        <button type="button" aria-label={m.zoom_out} title={m.zoom_out} onClick={() => onZoom(-1)} className={btn}>
          <span aria-hidden="true">−</span>
        </button>
      </div>
    </div>
  );
}
