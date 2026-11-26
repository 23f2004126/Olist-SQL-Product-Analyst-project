// Map colours come from the theme tokens in theme.css (emitted as CSS
// variables on :root), so the 3D scene never repeats a hex value.
import * as THREE from "three";

export interface MapColors {
  bg: THREE.Color;
  card: THREE.Color;
  line: THREE.Color;
  accent: THREE.Color;
  late: THREE.Color;
}

const token = (name: string) =>
  getComputedStyle(document.documentElement).getPropertyValue(`--color-${name}`).trim();

export function readMapColors(): MapColors {
  return {
    bg: new THREE.Color(token("bg")),
    card: new THREE.Color(token("card")),
    line: new THREE.Color(token("line")),
    accent: new THREE.Color(token("accent")),
    late: new THREE.Color(token("late")),
  };
}
