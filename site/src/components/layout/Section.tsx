// A page section: anchor id, eyebrow label, serif title, and a gentle
// fade-in on first view (skipped with reduced motion). Opacity only, no
// movement: a slide would shift the section after a jump link computes its
// target, so the heading would land in the wrong place.
import { motion, useReducedMotion } from "framer-motion";
import type { ReactNode } from "react";

interface Props {
  id: string;
  label?: string;
  title?: string;
  children: ReactNode;
  className?: string;
}

export function Section({ id, label, title, children, className = "" }: Props) {
  const reduce = useReducedMotion();
  const headingId = `${id}-title`;

  return (
    <section id={id} aria-labelledby={title ? headingId : undefined} className={className}>
      <motion.div
        initial={reduce ? false : { opacity: 0 }}
        whileInView={{ opacity: 1 }}
        viewport={{ once: true, margin: "0px 0px -15% 0px" }}
        transition={{ duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
      >
        {label && <p className="mb-3 text-xs font-medium uppercase tracking-[0.22em] text-accent">{label}</p>}
        {title && (
          <h2 id={headingId} className="mb-8 font-serif text-4xl leading-[1.05] text-ink sm:text-5xl">
            {title}
          </h2>
        )}
        {children}
      </motion.div>
    </section>
  );
}
