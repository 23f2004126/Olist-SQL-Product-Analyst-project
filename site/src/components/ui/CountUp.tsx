// Counts up to a display string (e.g. "13,181,027.13", "2.15%") when it
// scrolls into view. The final frame is always the exact display text from
// the data. With reduced motion it renders the final text immediately.
import { animate, useInView, useReducedMotion } from "framer-motion";
import { useEffect, useRef, useState } from "react";

interface Parsed {
  sign: string;
  value: number;
  decimals: number;
  suffix: string;
}

/** Split "−1,234.56 pp" into sign, number, decimals and suffix. */
function parseDisplay(display: string): Parsed | null {
  const m = display.match(/^(-?)([\d,]+)(?:\.(\d+))?(.*)$/);
  if (!m) return null;
  const decimals = m[3]?.length ?? 0;
  return {
    sign: m[1],
    value: Number(m[2].replace(/,/g, "") + (m[3] ? `.${m[3]}` : "")),
    decimals,
    suffix: m[4],
  };
}

const format = (p: Parsed, v: number) =>
  p.sign +
  v.toLocaleString("en-US", { minimumFractionDigits: p.decimals, maximumFractionDigits: p.decimals }) +
  p.suffix;

export function CountUp({ display, className }: { display: string; className?: string }) {
  const ref = useRef<HTMLSpanElement>(null);
  const inView = useInView(ref, { once: true, margin: "0px 0px -10% 0px" });
  const reduce = useReducedMotion();
  const parsed = parseDisplay(display);
  const [text, setText] = useState(reduce || !parsed ? display : format(parsed, 0));

  useEffect(() => {
    if (!inView || reduce || !parsed) {
      if (reduce || !parsed) setText(display);
      return;
    }
    const controls = animate(0, parsed.value, {
      duration: 1.4,
      ease: [0.16, 1, 0.3, 1],
      onUpdate: (v) => setText(format(parsed, v)),
      onComplete: () => setText(display), // land exactly on the data's text
    });
    return () => controls.stop();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [inView, reduce, display]);

  return (
    <span ref={ref} className={`tabular-nums ${className ?? ""}`}>
      <span className="sr-only">{display}</span>
      <span aria-hidden="true">{text}</span>
    </span>
  );
}
