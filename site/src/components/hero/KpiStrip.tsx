// The four headline KPIs from site.json (2 x 2 on phones, 4 across on desktop).
import { site } from "../../data/data";
import { NumberCard } from "../ui/NumberCard";

export function KpiStrip() {
  return (
    <ul className="mt-10 grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
      {site.hero.kpis.map((k) => (
        <li key={k.label}>
          <NumberCard number={k.number} label={k.label} />
        </li>
      ))}
    </ul>
  );
}
