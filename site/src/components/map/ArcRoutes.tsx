// All order arcs in TWO draw calls: one merged LineSegments for on-time
// routes and one for late routes. Additive blending makes busy corridors
// glow where many arcs overlap.
import { useMemo } from "react";
import * as THREE from "three";
import type { ArcData } from "./geometry";
import type { MapColors } from "./mapColors";

// Additive blending: overlapping arcs add up, so busy corridors brighten.
// On-time is kept low so the Sao Paulo hub glows without burning to white.
const ON_TIME_OPACITY = 0.06; // faint champagne
const LATE_OPACITY = 0.5; // brighter, so late routes stand out

function lineGeometry(positions: Float32Array) {
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  return g;
}

export function ArcRoutes({ arcs, colors, lateOnly }: { arcs: ArcData; colors: MapColors; lateOnly: boolean }) {
  const onTime = useMemo(() => lineGeometry(arcs.onTimePositions), [arcs]);
  const late = useMemo(() => lineGeometry(arcs.latePositions), [arcs]);

  return (
    <group>
      <lineSegments geometry={onTime} visible={!lateOnly} renderOrder={1}>
        <lineBasicMaterial
          color={colors.accent}
          transparent
          opacity={ON_TIME_OPACITY}
          blending={THREE.AdditiveBlending}
          depthWrite={false}
        />
      </lineSegments>
      <lineSegments geometry={late} renderOrder={2}>
        <lineBasicMaterial
          color={colors.late}
          transparent
          opacity={LATE_OPACITY}
          blending={THREE.AdditiveBlending}
          depthWrite={false}
        />
      </lineSegments>
    </group>
  );
}
