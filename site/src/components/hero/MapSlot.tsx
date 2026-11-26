// The hero map container. It always shows the static poster first; the live
// 3D map (a separate lazy chunk with three.js) loads on top of it and fades
// in once its first frame is drawn.
// The poster stays as the only view when:
//   - reduced motion is on (no moving scene at all),
//   - WebGL is not available, or
//   - the map fails to load or render (error boundary).
// The legend and caption come from site.json and show in every case.
import { useReducedMotion } from "framer-motion";
import { Component, lazy, Suspense, useState, type ReactNode } from "react";
import { site } from "../../data/data";
import { PHONE, useMediaQuery } from "../../hooks/useMediaQuery";

const HeroMap = lazy(() => import("../map/HeroMap"));

const POSTER_WIDE = `${import.meta.env.BASE_URL}hero-map-poster-wide.png`;
const POSTER_TALL = `${import.meta.env.BASE_URL}hero-map-poster-tall.png`;

function webglAvailable(): boolean {
  try {
    const c = document.createElement("canvas");
    return !!(c.getContext("webgl2") || c.getContext("webgl"));
  } catch {
    return false;
  }
}
const HAS_WEBGL = typeof document !== "undefined" && webglAvailable();

/** If the map chunk or WebGL fails, keep the poster instead of a blank box. */
class MapErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? null : this.props.children;
  }
}

function Poster() {
  return (
    <picture>
      <source media="(min-width: 640px)" srcSet={POSTER_WIDE} />
      <img
        src={POSTER_TALL}
        alt={site.map.poster_alt}
        className="absolute inset-0 h-full w-full object-cover"
        decoding="async"
      />
    </picture>
  );
}

function Legend() {
  return (
    <ul className="glass pointer-events-none absolute bottom-3 left-3 flex gap-4 rounded-full! px-4 py-2 text-xs sm:bottom-4 sm:left-4">
      {site.map.legend.map((item) => (
        <li key={item.id} className="flex items-center gap-2">
          <span
            aria-hidden="true"
            className={`h-2 w-2 rounded-full ${item.id === "late" ? "bg-late" : "bg-accent"}`}
          />
          <span className="text-muted">{item.label}</span>
          <span className="font-mono tabular-nums text-ink">{item.number.display}</span>
        </li>
      ))}
    </ul>
  );
}

export function MapSlot() {
  const reduce = useReducedMotion();
  const phone = useMediaQuery(PHONE);
  const [ready, setReady] = useState(false);
  const live = HAS_WEBGL && !reduce;

  return (
    <div className="mx-auto mt-14 max-w-6xl px-4 sm:px-6">
      <figure>
        <div
          id="map-root"
          className="relative aspect-[4/5] w-full overflow-hidden rounded-[var(--radius-card)] border border-line bg-bg sm:aspect-[16/8]"
        >
          <div role="img" aria-label={site.hero.map_label} className="absolute inset-0">
            <Poster />
          </div>
          {live && (
            <MapErrorBoundary>
              <Suspense fallback={null}>
                <div className={`absolute inset-0 transition-opacity duration-700 ${ready ? "opacity-100" : "opacity-0"}`}>
                  <HeroMap onReady={() => setReady(true)} />
                </div>
              </Suspense>
            </MapErrorBoundary>
          )}
          <Legend />
        </div>
        <figcaption className="mt-3 text-center text-xs text-muted">
          {site.map.caption.text}
          {phone && <> {site.map.phone_note}</>}
        </figcaption>
      </figure>
      <p className="mx-auto mt-8 max-w-xl px-4 text-center text-sm leading-relaxed text-ink/80">{site.hero.how_to_read}</p>
      <p className="mt-4 text-center text-xs uppercase tracking-[0.2em] text-muted">{site.hero.scroll_hint}</p>
    </div>
  );
}
