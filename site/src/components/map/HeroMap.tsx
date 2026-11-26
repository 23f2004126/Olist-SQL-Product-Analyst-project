// The live 3D map. This file is the entry of a separate, lazy-loaded chunk:
// three.js, React Three Fiber, the arc sample and the state figures only
// download when this component is first rendered (see MapSlot).
import { Canvas, type ThreeEvent } from "@react-three/fiber";
import { use, useEffect, useMemo, useRef, useState } from "react";
import arcsJson from "../../../data/map_arcs.json";
import mapJson from "../../../data/map.json";
import { site } from "../../data/data";
import type { MapArcsFile, MapMetaFile } from "../../data/types";
import { FINE_POINTER, PHONE, useMediaQuery } from "../../hooks/useMediaQuery";
import { ArcRoutes } from "./ArcRoutes";
import { BrazilStates, type StateFeature } from "./BrazilStates";
import { CameraRig, Drift, type ZoomApi } from "./CameraRig";
import { buildArcs } from "./geometry";
import { readMapColors } from "./mapColors";
import { MapTooltip, type HoverInfo } from "./MapTooltip";
import { MovingLights } from "./MovingLights";
import { RouteFilter, ZoomButtons } from "./MapControls";

const arcsFile = arcsJson as unknown as MapArcsFile;
const mapMeta = mapJson as unknown as MapMetaFile;

const DESKTOP_ARCS = 3000;
const PHONE_ARCS = 1000; // the sample is in random order, so the first 1,000 are a fair subset
const MAX_DPR = 2;

// State outlines live in public/geo and are fetched once, when this chunk
// loads. `use()` suspends until they arrive, so MapSlot keeps showing the
// poster in the meantime.
const geoPromise: Promise<{ features: StateFeature[] }> = fetch(
  `${import.meta.env.BASE_URL}geo/brazil-states.json`,
).then((r) => r.json());

/** Render only while the map is on screen and the tab is visible. */
function useShouldRender(target: React.RefObject<HTMLElement | null>) {
  const [onScreen, setOnScreen] = useState(true);
  const [tabVisible, setTabVisible] = useState(!document.hidden);
  useEffect(() => {
    const el = target.current;
    if (!el) return;
    const io = new IntersectionObserver(([entry]) => setOnScreen(entry.isIntersecting));
    io.observe(el);
    const onVis = () => setTabVisible(!document.hidden);
    document.addEventListener("visibilitychange", onVis);
    return () => {
      io.disconnect();
      document.removeEventListener("visibilitychange", onVis);
    };
  }, [target]);
  return onScreen && tabVisible;
}

export default function HeroMap({ onReady }: { onReady: () => void }) {
  const geo = use(geoPromise);
  const wrapper = useRef<HTMLDivElement>(null);
  const zoom = useRef<ZoomApi>(null);
  const finePointer = useMediaQuery(FINE_POINTER);
  const phone = useMediaQuery(PHONE);
  const active = useShouldRender(wrapper);
  const [lateOnly, setLateOnly] = useState(false);
  const [hover, setHover] = useState<HoverInfo | null>(null);

  const colors = useMemo(readMapColors, []);
  const arcs = useMemo(() => {
    const col = Object.fromEntries(arcsFile.columns.map((c, i) => [c, i]));
    return buildArcs(arcsFile.rows, col, phone ? PHONE_ARCS : DESKTOP_ARCS);
  }, [phone]);

  const onHover = (uf: string | null, e?: ThreeEvent<PointerEvent>) =>
    setHover(uf && e ? { uf, x: e.nativeEvent.offsetX, y: e.nativeEvent.offsetY } : null);

  const names = useMemo(() => Object.fromEntries(geo.features.map((f) => [f.properties.uf, f.properties.name])), [geo]);

  return (
    <div ref={wrapper} className="absolute inset-0">
      <Canvas
        aria-hidden="true"
        // flat = no tone mapping, so theme colours render exactly (#18181B stays #18181B)
        flat
        frameloop={active ? "always" : "never"}
        dpr={[1, MAX_DPR]}
        camera={{ fov: 32, near: 0.5, far: 100 }}
        gl={{ antialias: true, powerPreference: "high-performance" }}
        // touch screens: no controls are mounted, so let swipes scroll the page
        style={{ touchAction: finePointer ? "none" : "pan-y" }}
        onCreated={() => requestAnimationFrame(onReady)}
      >
        <color attach="background" args={[colors.bg]} />
        {/* Faint champagne rim: a low light from the camera side grazes the
            thin walls of the states that face the viewer. The tops are
            nearly parallel to it, so they stay card-coloured. */}
        <directionalLight position={[0, 0.35, 12]} intensity={1.1} color={colors.accent} />

        <CameraRig interactive={finePointer} zoomRef={zoom} />
        <Drift>
          <BrazilStates
            features={geo.features}
            colors={colors}
            hovered={hover?.uf ?? null}
            onHover={finePointer ? onHover : undefined}
          />
          <ArcRoutes arcs={arcs} colors={colors} lateOnly={lateOnly} />
          <MovingLights arcs={arcs} colors={colors} lateOnly={lateOnly} />
        </Drift>
      </Canvas>

      <RouteFilter lateOnly={lateOnly} onChange={setLateOnly} />
      {finePointer && <ZoomButtons onZoom={(d) => zoom.current?.zoom(d)} hint={site.map.controls_hint} />}
      {hover && (
        <MapTooltip
          info={hover}
          name={names[hover.uf]}
          figures={mapMeta.states[hover.uf]}
          containerWidth={wrapper.current?.clientWidth ?? 0}
        />
      )}
    </div>
  );
}
