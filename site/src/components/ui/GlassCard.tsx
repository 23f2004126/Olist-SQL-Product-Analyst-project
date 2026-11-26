// A subtle translucent card with a thin border. Styling lives in theme.css (.glass).
import type { ReactNode } from "react";

export function GlassCard({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <div className={`glass ${className}`}>{children}</div>;
}
