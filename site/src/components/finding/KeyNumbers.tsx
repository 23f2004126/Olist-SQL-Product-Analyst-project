// The 3-4 key-number cards chosen for a chapter in site.json.
import { site } from "../../data/data";
import type { Finding } from "../../data/types";
import { NumberCard } from "../ui/NumberCard";

export function KeyNumbers({ finding, cardIds }: { finding: Finding; cardIds: string[] }) {
  return (
    <div className="mt-8">
      <h3 className="sr-only">{site.ui.key_numbers}</h3>
      <ul className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
        {cardIds.map((id) => (
          <li key={id}>
            <NumberCard number={finding.key_numbers[id]} />
          </li>
        ))}
      </ul>
    </div>
  );
}
