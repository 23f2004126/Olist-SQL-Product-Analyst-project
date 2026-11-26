// About 60 small points of light, each travelling along one arc. When a light
// reaches the customer it jumps to another random arc, so over time it cycles
// through the routes. All lights are ONE Points object; each frame only
// its position buffer is rewritten.
import { useFrame } from "@react-three/fiber";
import { useEffect, useMemo, useRef } from "react";
import * as THREE from "three";
import { groundLength, pointOnArc, type ArcData } from "./geometry";
import type { MapColors } from "./mapColors";

export const LIGHT_COUNT = 60;
const BASE_SECONDS = 1.6; // travel time of a very short arc
const SECONDS_PER_UNIT = 0.45; // extra time per unit of distance
const SIZE = 0.16;

/** A soft round dot, drawn once into a small canvas texture. */
function makeDotTexture() {
  const c = document.createElement("canvas");
  c.width = c.height = 64;
  const g = c.getContext("2d")!;
  const grad = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  grad.addColorStop(0, "rgba(255,255,255,1)");
  grad.addColorStop(0.35, "rgba(255,255,255,0.55)");
  grad.addColorStop(1, "rgba(255,255,255,0)");
  g.fillStyle = grad;
  g.fillRect(0, 0, 64, 64);
  return new THREE.CanvasTexture(c);
}

export function MovingLights({ arcs, colors, lateOnly }: { arcs: ArcData; colors: MapColors; lateOnly: boolean }) {
  const pool = lateOnly ? arcs.lateIdx : arcs.allIdx;
  const count = Math.min(LIGHT_COUNT, pool.length);

  // Per light: which arc, how far along (0..1), and how long the trip takes.
  const state = useRef({ arc: new Int32Array(count), t: new Float32Array(count), dur: new Float32Array(count) });
  const geometry = useMemo(() => {
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.BufferAttribute(new Float32Array(count * 3), 3));
    g.setAttribute("color", new THREE.BufferAttribute(new Float32Array(count * 3), 3));
    return g;
  }, [count]);
  const texture = useMemo(makeDotTexture, []);

  const assign = (k: number, t: number) => {
    const s = state.current;
    const i = pool[Math.floor(Math.random() * pool.length)];
    s.arc[k] = i;
    s.t[k] = t;
    s.dur[k] = BASE_SECONDS + groundLength(arcs.curves, i) * SECONDS_PER_UNIT;
    const c = arcs.late[i] ? colors.late : colors.accent;
    (geometry.attributes.color as THREE.BufferAttribute).setXYZ(k, c.r, c.g, c.b);
    geometry.attributes.color.needsUpdate = true;
  };

  // (Re)start all lights at random points along their trips, so they don't
  // move in step. Runs again when the "Late only" filter changes the pool.
  useEffect(() => {
    state.current = { arc: new Int32Array(count), t: new Float32Array(count), dur: new Float32Array(count) };
    for (let k = 0; k < count; k++) assign(k, Math.random());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pool, count, geometry]);

  const p = useMemo(() => new THREE.Vector3(), []);
  useFrame((_, delta) => {
    const s = state.current;
    const pos = geometry.attributes.position as THREE.BufferAttribute;
    const dt = Math.min(delta, 0.1); // after a pause, don't jump far
    for (let k = 0; k < count; k++) {
      s.t[k] += dt / s.dur[k];
      if (s.t[k] >= 1) assign(k, 0); // arrived: pick a new route
      pointOnArc(arcs.curves, s.arc[k], s.t[k], p);
      pos.setXYZ(k, p.x, p.y, p.z);
    }
    pos.needsUpdate = true;
  });

  return (
    <points geometry={geometry} renderOrder={3}>
      <pointsMaterial
        size={SIZE}
        map={texture}
        vertexColors
        transparent
        depthWrite={false}
        blending={THREE.AdditiveBlending}
        sizeAttenuation
      />
    </points>
  );
}
