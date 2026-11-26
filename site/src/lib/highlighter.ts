// Shiki, loaded only when a "View SQL" panel opens (this module is imported
// dynamically). Uses the small core build, the JavaScript regex engine (no
// WebAssembly download) and only the SQL grammar. Colours come from theme.css.
import { createHighlighterCore, type HighlighterCore, type ThemeRegistrationRaw } from "shiki/core";
import { createJavaScriptRegexEngine } from "shiki/engine/javascript";
import { token } from "./token";

function graphiteTheme(): ThemeRegistrationRaw {
  return {
    name: "graphite",
    type: "dark",
    colors: { "editor.background": "#00000000", "editor.foreground": token("ink") },
    settings: [
      { settings: { foreground: token("ink"), background: "#00000000" } },
      { scope: ["comment", "punctuation.definition.comment"], settings: { foreground: token("muted"), fontStyle: "italic" } },
      { scope: ["keyword", "storage", "keyword.other.DML.sql", "keyword.other.sql"], settings: { foreground: token("accent") } },
      { scope: ["string", "string.quoted"], settings: { foreground: token("slate-text") } },
      { scope: ["constant.numeric", "constant.language"], settings: { foreground: token("late-text") } },
      { scope: ["support.function", "entity.name.function"], settings: { foreground: token("ink"), fontStyle: "bold" } },
      { scope: ["keyword.operator"], settings: { foreground: token("muted") } },
    ],
  };
}

let highlighter: Promise<HighlighterCore> | null = null;

function getHighlighter() {
  highlighter ??= createHighlighterCore({
    themes: [graphiteTheme()],
    langs: [import("@shikijs/langs/sql")],
    engine: createJavaScriptRegexEngine(),
  });
  return highlighter;
}

/** Highlight SQL to HTML, marking the given 1-based line numbers. */
export async function highlightSql(code: string, annotatedLines: number[]): Promise<string> {
  const h = await getHighlighter();
  const marked = new Set(annotatedLines);
  return h.codeToHtml(code, {
    lang: "sql",
    theme: "graphite",
    transformers: [
      {
        line(node, line) {
          if (marked.has(line)) this.addClassToHast(node, "annotated");
        },
      },
    ],
  });
}
