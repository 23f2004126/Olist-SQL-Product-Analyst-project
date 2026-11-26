// The ordered list of page sections, used by the chapter rail, the mobile
// progress bar and the section anchors. Labels come from site.json.
import { site } from "./data";

export interface SectionInfo {
  id: string;
  short: string; // label in the rail
  number?: string; // chapter number, e.g. "01"
}

export const chapterNumber = (index: number) => String(index + 1).padStart(2, "0");

export const sections: SectionInfo[] = [
  { id: "top", short: site.meta.nav_title },
  { id: "question", short: site.question.label },
  ...site.chapters.map((c, i) => ({
    id: `chapter-${c.id}`,
    short: c.title,
    number: chapterNumber(i),
  })),
  { id: "recommendations", short: site.recommendations.label },
  { id: "under-the-hood", short: site.under_the_hood.label },
  { id: "limitations", short: site.limitations.label },
];
