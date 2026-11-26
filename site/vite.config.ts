import { readFileSync } from "node:fs";
import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// Size of public/og-image.png (made by scripts/make-og-image.mjs).
const OG_SIZE = { width: 1200, height: 630 };

/**
 * Writes the page title, description and link-preview tags into index.html
 * at build time, from site/data/site.json. Link-preview crawlers (LinkedIn,
 * WhatsApp, Slack) don't run JavaScript, so these must be in the HTML.
 * Open Graph images need an absolute URL: set links.site in
 * docs/site_copy.json (or SITE_URL at build time) once the site is deployed.
 */
function pageMeta(): Plugin {
  return {
    name: "olist-page-meta",
    transformIndexHtml(html) {
      const site = JSON.parse(readFileSync(new URL("./data/site.json", import.meta.url), "utf-8"));
      const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
      const base = (process.env.SITE_URL || site.links.site || "").replace(/\/?$/, "/");
      const abs = (p: string) => (base !== "/" ? new URL(p, base).href : p);
      const { title, description, og_image, og_image_alt } = site.meta;
      const tags = [
        `<meta name="description" content="${esc(description)}" />`,
        `<meta property="og:type" content="website" />`,
        `<meta property="og:title" content="${esc(title)}" />`,
        `<meta property="og:description" content="${esc(description)}" />`,
        `<meta property="og:image" content="${esc(abs(og_image))}" />`,
        `<meta property="og:image:width" content="${OG_SIZE.width}" />`,
        `<meta property="og:image:height" content="${OG_SIZE.height}" />`,
        `<meta property="og:image:alt" content="${esc(og_image_alt)}" />`,
        `<meta name="twitter:card" content="summary_large_image" />`,
        `<meta name="twitter:title" content="${esc(title)}" />`,
        `<meta name="twitter:description" content="${esc(description)}" />`,
        `<meta name="twitter:image" content="${esc(abs(og_image))}" />`,
        ...(base !== "/" ? [`<meta property="og:url" content="${esc(base)}" />`, `<link rel="canonical" href="${esc(base)}" />`] : []),
      ];
      return html
        .replace(/<title>.*?<\/title>/, `<title>${esc(title)}</title>`)
        .replace("<!-- page-meta -->", tags.join("\n    "));
    },
  };
}

// Relative base so the built site works from any folder or static host.
export default defineConfig({
  base: "./",
  plugins: [react(), tailwindcss(), pageMeta()],
});
