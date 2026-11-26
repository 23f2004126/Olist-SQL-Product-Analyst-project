// Read a colour token from theme.css at runtime (for code that can't use
// Tailwind classes: Shiki now, d3 and three.js later).
export function token(name: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(`--color-${name}`).trim();
}
