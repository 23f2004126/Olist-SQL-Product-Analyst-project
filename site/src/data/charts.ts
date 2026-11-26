// Chart rows and chart copy (site/data/charts.json). Imported only by the
// chart components, so it ships in the lazily loaded chart chunk.
import chartsJson from "../../data/charts.json";
import type { ChartsFile } from "./types";

export const charts = chartsJson as unknown as ChartsFile;
