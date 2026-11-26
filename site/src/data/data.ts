// Single entry point for site data. Small files are bundled; queries.json and
// pipelines.json are loaded on demand (when a panel opens, or at idle time)
// to keep first load light. charts.json is read only by the chart chunk
// (src/data/charts.ts).
import siteJson from "../../data/site.json";
import kpisJson from "../../data/kpis.json";
import findingsJson from "../../data/findings.json";
import type {
  FindingsFile,
  KpisFile,
  PipelinesFile,
  QueriesFile,
  SiteFile,
} from "./types";

export const site = siteJson as unknown as SiteFile;
export const kpis = kpisJson as unknown as KpisFile;
export const findingsFile = findingsJson as unknown as FindingsFile;

export const findingById = Object.fromEntries(
  findingsFile.findings.map((f) => [f.id, f]),
);
export const recommendationById = Object.fromEntries(
  findingsFile.recommendations.map((r) => [r.id, r]),
);

let pipelinesPromise: Promise<PipelinesFile> | null = null;
let pipelinesLoaded: PipelinesFile | null = null;
/** Loads pipelines.json once ("How we got this" funnels and checks). */
export function loadPipelines(): Promise<PipelinesFile> {
  pipelinesPromise ??= import("../../data/pipelines.json").then((m) => {
    pipelinesLoaded = m.default as unknown as PipelinesFile;
    return pipelinesLoaded;
  });
  return pipelinesPromise;
}
/** pipelines.json if it has already loaded, else null. */
export const pipelinesIfLoaded = () => pipelinesLoaded;

let queriesPromise: Promise<QueriesFile> | null = null;
/** Loads queries.json once, on first request. */
export function loadQueries(): Promise<QueriesFile> {
  queriesPromise ??= import("../../data/queries.json").then(
    (m) => m.default as unknown as QueriesFile,
  );
  return queriesPromise;
}
