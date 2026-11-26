// Page structure, top to bottom. Each section is its own component.
import { MotionConfig } from "framer-motion";
import { site } from "./data/data";
import { SmoothScroll } from "./hooks/SmoothScroll";
import { TopBar } from "./components/layout/TopBar";
import { ChapterRail } from "./components/layout/ChapterRail";
import { Hero } from "./components/hero/Hero";
import { QuestionSection } from "./components/question/QuestionSection";
import { FindingChapter } from "./components/finding/FindingChapter";
import { RecommendationsSection } from "./components/recs/RecommendationsSection";
import { UnderTheHood } from "./components/hood/UnderTheHood";
import { Limitations } from "./components/footer/Limitations";
import { Footer } from "./components/footer/Footer";

export default function App() {
  return (
    // reducedMotion="user": Framer Motion follows the OS prefers-reduced-motion setting
    <MotionConfig reducedMotion="user">
      <SmoothScroll>
        <a
          href="#main"
          className="sr-only z-50 rounded bg-accent px-3 py-2 text-bg focus:not-sr-only focus:fixed focus:left-4 focus:top-4"
        >
          {site.ui.skip_to_content}
        </a>
        <TopBar />
        <ChapterRail />
        <Hero />
        <main id="main" className="mx-auto max-w-4xl space-y-32 px-4 pt-32 sm:space-y-40 sm:px-6">
          <QuestionSection />
          {site.chapters.map((c, i) => (
            <FindingChapter key={c.id} chapter={c} index={i} />
          ))}
          <RecommendationsSection />
          <UnderTheHood />
          <Limitations />
        </main>
        <Footer />
      </SmoothScroll>
    </MotionConfig>
  );
}
