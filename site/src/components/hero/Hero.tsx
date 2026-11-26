// Section 0: title, subtitle, headline KPIs, and the full-width 3D map.
import { site } from "../../data/data";
import { KpiStrip } from "./KpiStrip";
import { MapSlot } from "./MapSlot";

export function Hero() {
  return (
    <section id="top" aria-labelledby="hero-title" className="pt-28 sm:pt-36">
      <div className="mx-auto max-w-4xl px-4 sm:px-6">
        <p className="mb-5 text-xs font-medium uppercase tracking-[0.24em] text-accent">{site.hero.eyebrow}</p>
        <h1 id="hero-title" className="font-serif text-[2.75rem] leading-[1.02] text-ink sm:text-7xl">
          {site.meta.title}
        </h1>
        <p className="mt-6 max-w-2xl text-base leading-relaxed text-muted sm:text-lg">{site.meta.subtitle.text}</p>
        <KpiStrip />
      </div>
      <MapSlot />
    </section>
  );
}
