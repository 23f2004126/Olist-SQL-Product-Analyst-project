import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
// Self-hosted fonts (no external requests)
import "@fontsource/instrument-serif/400.css";
import "@fontsource-variable/inter";
import "@fontsource-variable/jetbrains-mono";
import "./theme/theme.css";
import App from "./App";

// The page title, description and link-preview tags are written into
// index.html at build time from site.json (see vite.config.ts).

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
