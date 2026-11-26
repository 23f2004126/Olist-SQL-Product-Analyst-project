// Camera framing, slow drift and (desktop only) limited orbit + zoom.
// - Framing: the map is seen from 40 degrees off vertical. The distance grows
//   on narrow containers (phones) so the whole country still fits.
// - Drift: the map group sways a few degrees left and right (see Drift below).
// - Desktop: drag to orbit within limits; zoom with buttons, a trackpad pinch
//   or Ctrl + wheel. A plain wheel is left alone, so the page scrolls.
// - Touch screens: no controls at all, so swipes scroll the page.
import { CameraControls, CameraControlsImpl } from "@react-three/drei";
import { useFrame, useThree } from "@react-three/fiber";
import { useEffect, useImperativeHandle, useRef, type ReactNode, type Ref } from "react";
import type * as THREE from "three";

const POLAR = (40 * Math.PI) / 180; // tilt: 40 degrees from looking straight down
const BASE_DISTANCE = 14.6; // fits the map's height in a wide container
// Look slightly south of the map centre: with the tilt, the near (southern)
// half looks bigger, so this keeps Rio Grande do Sul inside the frame.
const TARGET_Z = 0.55;
// Seen at this tilt (and allowing for the drift) the map is about 1.4 times
// as wide as it is tall on screen. Containers narrower than that (phones)
// need the camera further back so the width fits; wider containers are
// limited by height instead.
const MAP_SCREEN_ASPECT = 1.4;
const ZOOM_MIN = 0.62; // closest = 62% of the base distance
const ZOOM_MAX = 1.15;
const ORBIT_POLAR = (14 * Math.PI) / 180; // allowed tilt change either way
const ORBIT_AZIMUTH = (28 * Math.PI) / 180; // allowed turn either way
const ZOOM_STEP = 2; // scene units per button press

export interface ZoomApi {
  zoom: (direction: 1 | -1) => void;
}

/** Camera position for a distance, tilt and turn (spherical coordinates around the map centre). */
function cameraPosition(distance: number, polar: number, azimuth: number): [number, number, number] {
  return [
    distance * Math.sin(polar) * Math.sin(azimuth),
    distance * Math.cos(polar),
    distance * Math.sin(polar) * Math.cos(azimuth),
  ];
}

export function CameraRig({ interactive, zoomRef }: { interactive: boolean; zoomRef: Ref<ZoomApi> }) {
  const { camera, size, gl } = useThree();
  const controls = useRef<CameraControlsImpl>(null);
  const base = BASE_DISTANCE * Math.max(1, MAP_SCREEN_ASPECT / (size.width / size.height));

  // Frame the map whenever the container's shape changes.
  useEffect(() => {
    const [x, y, z] = cameraPosition(base, POLAR, 0);
    const c = controls.current;
    if (c) {
      c.minDistance = base * ZOOM_MIN;
      c.maxDistance = base * ZOOM_MAX;
      c.setLookAt(x, y, z + TARGET_Z, 0, 0, TARGET_Z, false);
    } else {
      camera.position.set(x, y, z + TARGET_Z);
      camera.lookAt(0, 0, TARGET_Z);
    }
  }, [base, camera]);

  // Zoom buttons call this through the ref.
  useImperativeHandle(zoomRef, () => ({ zoom: (dir) => controls.current?.dolly(dir * ZOOM_STEP, true) }), []);

  // Pinch on a trackpad arrives as wheel + ctrlKey. Zoom on that, and let
  // every other wheel event through to the page.
  useEffect(() => {
    if (!interactive) return;
    const el = gl.domElement;
    const onWheel = (e: WheelEvent) => {
      if (!e.ctrlKey) return;
      e.preventDefault(); // stop the browser's page zoom
      controls.current?.dolly(-e.deltaY * 0.02, true);
    };
    el.addEventListener("wheel", onWheel, { passive: false });
    return () => el.removeEventListener("wheel", onWheel);
  }, [interactive, gl]);

  if (!interactive) return null;
  const { ACTION } = CameraControlsImpl;
  return (
    <CameraControls
      ref={controls}
      makeDefault
      minPolarAngle={POLAR - ORBIT_POLAR}
      maxPolarAngle={POLAR + ORBIT_POLAR}
      minAzimuthAngle={-ORBIT_AZIMUTH}
      maxAzimuthAngle={ORBIT_AZIMUTH}
      mouseButtons={{ left: ACTION.ROTATE, middle: ACTION.NONE, right: ACTION.NONE, wheel: ACTION.NONE }}
      smoothTime={0.6}
    />
  );
}

/** Slow left-right sway of the whole map: about 6 degrees over ~80 seconds. */
export function Drift({ children }: { children: ReactNode }) {
  const group = useRef<THREE.Group>(null);
  useFrame(({ clock }) => {
    if (group.current) group.current.rotation.y = Math.sin(clock.elapsedTime * 0.08) * 0.1;
  });
  return <group ref={group}>{children}</group>;
}
