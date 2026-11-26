// Checks WCAG contrast for every text colour token against the page and card
// backgrounds in src/theme/theme.css. Fails (exit 1) if any is below AA (4.5:1).
// Run: npm run contrast
import { readFileSync } from "node:fs";

const css = readFileSync(new URL("../src/theme/theme.css", import.meta.url), "utf8");
const token = (name) => {
  const m = css.match(new RegExp(`--color-${name}:\\s*(#[0-9a-fA-F]{6})`));
  if (!m) throw new Error(`token --color-${name} not found`);
  return m[1];
};

const lum = (hex) => {
  const c = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
};
const ratio = (a, b) => {
  const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
};

const texts = ["ink", "muted", "accent", "slate-text", "late-text"];
const backgrounds = ["bg", "card"];
let failed = false;
for (const t of texts) {
  for (const b of backgrounds) {
    const r = ratio(token(t), token(b));
    const ok = r >= 4.5;
    if (!ok) failed = true;
    console.log(`${ok ? "PASS" : "FAIL"}  ${t.padEnd(11)} on ${b.padEnd(5)} ${r.toFixed(2)}:1`);
  }
}
// Fill-only tokens: reported for reference (3:1 is the AA minimum for graphics)
for (const t of ["slate", "late"]) {
  console.log(`info  ${t.padEnd(11)} on bg    ${ratio(token(t), token("bg")).toFixed(2)}:1 (fills/marks only)`);
}
process.exit(failed ? 1 : 0);
