// Renders the link-preview image (public/og-image.png, 1200x630) from the
// hero of the running site, and the PNG icons (favicon-32.png,
// apple-touch-icon.png) from public/favicon.svg, with headless Chrome.
// Usage (dev server running): node scripts/make-og-image.mjs http://localhost:5173/
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const URL_BASE = process.argv[2] ?? "http://localhost:5173/";
const PUBLIC = new URL("../public/", import.meta.url);
const CHROME = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = 9341;
const OG = { width: 1200, height: 630 };

const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`, `--user-data-dir=${mkdtempSync(join(tmpdir(), "og-"))}`,
  "--no-first-run", "--hide-scrollbars", "--force-color-profile=srgb", "about:blank"], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let target;
for (let i = 0; i < 60 && !target; i++) {
  try { target = (await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json()).find((t) => t.type === "page"); } catch {}
  await sleep(250);
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener("open", r, { once: true }));
let id = 0; const pending = new Map();
ws.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
const send = (method, params = {}) => new Promise((res, rej) => { const i = ++id;
  pending.set(i, (m) => (m.error ? rej(new Error(method + ": " + m.error.message)) : res(m.result))); ws.send(JSON.stringify({ id: i, method, params })); });
const js = (expression) => send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
const png = async (clip) => Buffer.from((await send("Page.captureScreenshot", { format: "png", ...(clip ? { clip } : {}) })).data, "base64");
await send("Page.enable"); await send("Runtime.enable");

// ---- icons: the SVG drawn at each size on a transparent page
const svg = readFileSync(new URL("favicon.svg", PUBLIC), "utf-8");
await send("Emulation.setDefaultBackgroundColorOverride", { color: { r: 0, g: 0, b: 0, a: 0 } });
for (const [name, size] of [["favicon-32.png", 32], ["apple-touch-icon.png", 180]]) {
  await send("Emulation.setDeviceMetricsOverride", { width: size, height: size, deviceScaleFactor: 1, mobile: false });
  await send("Page.navigate", { url: `data:text/html,${encodeURIComponent(`<style>html,body{margin:0;background:transparent}</style><img src="data:image/svg+xml;base64,${Buffer.from(svg).toString("base64")}" width="${size}" height="${size}">`)}` });
  await sleep(500);
  writeFileSync(new URL(name, PUBLIC), await png());
  console.log("wrote public/" + name);
}
await send("Emulation.setDefaultBackgroundColorOverride", {});

// ---- link-preview image: the hero (title, KPIs, the live map), framed at
// 1200x630. The page is laid out at a wider width and scaled down so the
// title, the headline numbers and the top of the map all fit.
const LAYOUT_W = Number(process.env.OG_LAYOUT_W ?? 1600);
const scale = OG.width / LAYOUT_W;
// Tall viewport: WebGL only draws inside it, and the crop starts below the top.
await send("Emulation.setDeviceMetricsOverride", { width: LAYOUT_W, height: Math.round(OG.height / scale) + 400, deviceScaleFactor: 1, mobile: false });
await send("Page.navigate", { url: URL_BASE });
await sleep(7000); // map chunk, geo data and first frames
await js(`(() => { const s = document.createElement('style');
  // fixed header, chapter rail and the map's control pills stay out of the card
  s.textContent = 'header, nav[aria-label], #map-root .glass { visibility: hidden !important; }';
  document.head.appendChild(s); return true; })()`);
await sleep(1500);
// Start just above the eyebrow line, so the card isn't mostly top padding.
const { result } = await js(`Math.max(0, document.querySelector('#hero-title').previousElementSibling.getBoundingClientRect().top + scrollY - 48)`);
const top = result.value;
writeFileSync(new URL("og-image.png", PUBLIC), await png({ x: 0, y: top, width: LAYOUT_W, height: OG.height / scale, scale }));
console.log(`wrote public/og-image.png (${OG.width}x${OG.height})`);
ws.close(); chrome.kill();
