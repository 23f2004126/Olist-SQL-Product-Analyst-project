// Reading progress for the chapter rail and the mobile bar.
// - progress: a 0..1 motion value for scaleX / scaleY. Smoothed with a spring,
//   except under prefers-reduced-motion, where it follows the scroll exactly.
// - percent: a whole number 0..100 for the progress bar's aria-valuenow.
import { useMotionValueEvent, useReducedMotion, useScroll, useSpring } from "framer-motion";
import { useState } from "react";

export function useReadingProgress() {
  const reduce = useReducedMotion();
  const { scrollYProgress } = useScroll();
  // Hooks always run in the same order; only the choice of value changes.
  const smoothed = useSpring(scrollYProgress, { stiffness: 200, damping: 40, restDelta: 0.001 });
  const [percent, setPercent] = useState(0);

  useMotionValueEvent(scrollYProgress, "change", (v) => {
    const next = Math.round(v * 100);
    setPercent((prev) => (prev === next ? prev : next)); // re-render only when the whole number changes
  });

  return { progress: reduce ? scrollYProgress : smoothed, percent };
}
