// A collapsed panel with an accessible toggle button. Children render only
// while the panel is open, so heavy content (Shiki) loads on demand.
// A panel with an `id` can also be opened from elsewhere on the page with
// openPanel(id) (e.g. "See it used" in the SQL techniques).
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { useEffect, useId, useRef, useState, type ReactNode } from "react";

interface Props {
  label: string;
  icon?: ReactNode;
  /** Element id; also the name openPanel() uses. */
  id?: string;
  children: ReactNode;
}

const OPEN_EVENT = "olist:open-panel";

/** Opens the Disclosure with this id and moves keyboard focus to its toggle. */
export function openPanel(id: string) {
  window.dispatchEvent(new CustomEvent(OPEN_EVENT, { detail: id }));
}

export function Disclosure({ label, icon, id, children }: Props) {
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const reduce = useReducedMotion();
  const button = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!id) return;
    const onOpen = (e: Event) => {
      if ((e as CustomEvent<string>).detail !== id) return;
      setOpen(true);
      button.current?.focus({ preventScroll: true });
    };
    window.addEventListener(OPEN_EVENT, onOpen);
    return () => window.removeEventListener(OPEN_EVENT, onOpen);
  }, [id]);

  return (
    <div id={id} className="scroll-mt-24 border-t border-line">
      <button
        ref={button}
        type="button"
        aria-expanded={open}
        aria-controls={open ? panelId : undefined} // only point at the panel while it exists
        onClick={() => setOpen((o) => !o)}
        className="group flex w-full items-center justify-between gap-4 py-4 text-left text-sm font-medium text-ink transition-colors hover:text-accent"
      >
        <span className="flex items-center gap-3">
          {icon}
          {label}
        </span>
        <span
          aria-hidden="true"
          className={`text-muted transition-transform duration-300 group-hover:text-accent ${open ? "rotate-45" : ""}`}
        >
          +
        </span>
      </button>
      <AnimatePresence initial={false}>
        {open && (
          <motion.div
            id={panelId}
            initial={reduce ? false : { height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={reduce ? undefined : { height: 0, opacity: 0 }}
            transition={{ duration: 0.35, ease: [0.16, 1, 0.3, 1] }}
            className="overflow-hidden"
          >
            <div className="pb-6">{children}</div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
