// True while a CSS media query matches; updates when it changes
// (e.g. rotating a phone, or switching reduced motion on in the OS).
import { useSyncExternalStore } from "react";

export function useMediaQuery(query: string): boolean {
  return useSyncExternalStore(
    (onChange) => {
      const mql = window.matchMedia(query);
      mql.addEventListener("change", onChange);
      return () => mql.removeEventListener("change", onChange);
    },
    () => window.matchMedia(query).matches,
    () => false,
  );
}

/** A mouse or trackpad: hover works and dragging won't fight page scroll. */
export const FINE_POINTER = "(hover: hover) and (pointer: fine)";
/** Phone-sized screens (Tailwind's sm breakpoint). */
export const PHONE = "(max-width: 639px)";
