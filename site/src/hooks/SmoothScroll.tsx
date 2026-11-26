// Lenis smooth scrolling, plus a scrollTo(id) helper shared through context.
// With prefers-reduced-motion, Lenis is not started and jumps are instant.
import Lenis from "lenis";
import { createContext, useContext, useEffect, useRef, type ReactNode } from "react";
import { useReducedMotion } from "framer-motion";

// Keep headings clear of the fixed header. Its height differs on phones (it
// adds a progress row), so measure it instead of hardcoding a number.
const GAP_BELOW_HEADER = 16;
const headerOffset = () => -((document.querySelector("header")?.offsetHeight ?? 0) + GAP_BELOW_HEADER);

type ScrollTo = (id: string) => void;
const ScrollContext = createContext<ScrollTo>(() => {});

export function SmoothScroll({ children }: { children: ReactNode }) {
  const reduce = useReducedMotion();
  const lenisRef = useRef<Lenis | null>(null);

  useEffect(() => {
    if (reduce) return;
    const lenis = new Lenis({ lerp: 0.1, smoothWheel: true });
    lenisRef.current = lenis;
    let frame = 0;
    const raf = (time: number) => {
      lenis.raf(time);
      frame = requestAnimationFrame(raf);
    };
    frame = requestAnimationFrame(raf);
    return () => {
      cancelAnimationFrame(frame);
      lenis.destroy();
      lenisRef.current = null;
    };
  }, [reduce]);

  const scrollTo: ScrollTo = (id) => {
    const el = document.getElementById(id);
    if (!el) return;
    const offset = headerOffset();
    if (lenisRef.current) {
      lenisRef.current.scrollTo(el, { offset });
    } else {
      const y = el.getBoundingClientRect().top + window.scrollY + offset;
      window.scrollTo({ top: y, behavior: "auto" });
    }
    history.replaceState(null, "", `#${id}`);
  };

  return <ScrollContext.Provider value={scrollTo}>{children}</ScrollContext.Provider>;
}

export const useScrollTo = () => useContext(ScrollContext);
