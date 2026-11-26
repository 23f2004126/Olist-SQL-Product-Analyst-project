// Typed access to a chart's labels in charts.json (items[id].labels).
import { charts } from "../../../data/charts";

export function labelsFor(chartId: string) {
  const labels = charts.items[chartId].labels;
  return {
    /** A plain label. */
    t: (key: string) => {
      const v = labels[key];
      return typeof v === "string" ? v : key;
    },
    /** A group of labels, e.g. stage names keyed by column. */
    group: (key: string) => {
      const v = labels[key];
      return typeof v === "object" ? v : {};
    },
  };
}
