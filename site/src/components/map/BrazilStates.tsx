// The 27 states as thin extruded shapes with hairline borders.
// One mesh per state (so hovering can tell states apart) and ONE merged line
// geometry for all borders.
import { useMemo } from "react";
import * as THREE from "three";
import type { ThreeEvent } from "@react-three/fiber";
import { bordersToSegments, polygonsToShapes, STATE_DEPTH } from "./geometry";
import type { MapColors } from "./mapColors";

export interface StateFeature {
  properties: { code: string; uf: string; name: string };
  geometry: { type: "MultiPolygon"; coordinates: [number, number][][][] };
}

interface Props {
  features: StateFeature[];
  colors: MapColors;
  hovered: string | null;
  /** Only passed on devices with a mouse: hover shows the tooltip. */
  onHover?: (uf: string | null, e?: ThreeEvent<PointerEvent>) => void;
}

// Shapes are drawn in the X-Y plane; rotating -90 degrees around X lays them
// flat, with the extrusion pointing up (+Y) and north pointing away (-Z).
const FLAT: [number, number, number] = [-Math.PI / 2, 0, 0];

export function BrazilStates({ features, colors, hovered, onHover }: Props) {
  // Built once: geometry for each state and the merged border lines.
  const states = useMemo(
    () =>
      features.map((f) => ({
        uf: f.properties.uf,
        geometry: new THREE.ExtrudeGeometry(polygonsToShapes(f.geometry.coordinates), {
          depth: STATE_DEPTH,
          bevelEnabled: false,
        }),
      })),
    [features],
  );
  const borders = useMemo(() => {
    const g = new THREE.BufferGeometry();
    const z = STATE_DEPTH + 0.002; // just above the top faces, so lines don't flicker
    g.setAttribute("position", new THREE.BufferAttribute(bordersToSegments(features.map((f) => f.geometry.coordinates), z), 3));
    return g;
  }, [features]);

  // Hovered state is lifted slightly towards the accent colour.
  const hoverColor = useMemo(() => colors.card.clone().lerp(colors.accent, 0.12), [colors]);
  // Base colour that reflects the lights: a dim champagne. The low rim light
  // hits the walls almost head-on (champagne edge) but the tops at a grazing
  // angle, so the tops stay close to the card colour.
  const rimTint = useMemo(() => colors.accent.clone().multiplyScalar(0.35), [colors]);

  return (
    <group rotation={FLAT}>
      {states.map((s) => (
        <mesh
          key={s.uf}
          geometry={s.geometry}
          onPointerMove={
            onHover &&
            ((e) => {
              e.stopPropagation(); // only the state under the pointer, not the ones behind
              onHover(s.uf, e);
            })
          }
          onPointerOut={onHover && (() => onHover(null))}
        >
          {/* Emissive = the card colour, so the tops read as #18181B whatever the
              lighting; the lights only add the champagne rim on the walls. */}
          <meshStandardMaterial
            color={rimTint}
            emissive={s.uf === hovered ? hoverColor : colors.card}
            roughness={0.7}
            metalness={0}
          />
        </mesh>
      ))}
      <lineSegments geometry={borders}>
        <lineBasicMaterial color={colors.line} />
      </lineSegments>
    </group>
  );
}
