// Pure maths for the hero map: projection, state shapes and arc curves.
// No React here, so each step can be read and tested on its own.
//
// World layout: the map lies flat on the X-Z plane, Y points up.
//   x = east-west, z = north-south (north is -z, away from the camera).
import * as THREE from "three";

/* ---------- projection ---------------------------------------------------- */

// Centre of Brazil (approx.) and scene scale. An equirectangular projection
// with longitude shrunk by cos(latitude) keeps shapes close to true at this
// size, and is simple to explain.
const LNG0 = -52.5;
const LAT0 = -14.5;
const SCALE = 0.25; // scene units per degree
const COS_LAT0 = Math.cos((LAT0 * Math.PI) / 180);

/** Longitude/latitude -> plane coordinates (x, y) used for 2D shapes. */
export function project(lng: number, lat: number): [number, number] {
  return [(lng - LNG0) * COS_LAT0 * SCALE, (lat - LAT0) * SCALE];
}

/* ---------- states -------------------------------------------------------- */

export const STATE_DEPTH = 0.12; // extrusion height of each state

type Ring = [number, number][];

/** GeoJSON MultiPolygon coordinates -> THREE.Shapes (outer ring + holes). */
export function polygonsToShapes(polygons: Ring[][]): THREE.Shape[] {
  return polygons.map(([outer, ...holes]) => {
    const shape = new THREE.Shape(outer.map(([lng, lat]) => new THREE.Vector2(...project(lng, lat))));
    for (const h of holes) {
      shape.holes.push(new THREE.Path(h.map(([lng, lat]) => new THREE.Vector2(...project(lng, lat)))));
    }
    return shape;
  });
}

/**
 * Every ring of every state as line segments lying on top of the extruded
 * shapes, merged into ONE position array (one draw call for all borders).
 * Shapes are built in the X-Y plane and rotated flat later, so this uses
 * the same (x, y) and puts the height in z.
 */
export function bordersToSegments(allPolygons: Ring[][][], z: number): Float32Array {
  const out: number[] = [];
  for (const polygons of allPolygons) {
    for (const rings of polygons) {
      for (const ring of rings) {
        for (let i = 0; i < ring.length - 1; i++) {
          const [x1, y1] = project(...ring[i]);
          const [x2, y2] = project(...ring[i + 1]);
          out.push(x1, y1, z, x2, y2, z);
        }
      }
    }
  }
  return new Float32Array(out);
}

/* ---------- arcs ---------------------------------------------------------- */

export const ARC_SEGMENTS = 24; // straight pieces per curve
const ARC_BASE = STATE_DEPTH + 0.01; // start/end just above the state tops
const HEIGHT_PER_UNIT = 0.32; // arc peak height per unit of distance
const MIN_HEIGHT = 0.12;

export interface ArcData {
  /** Per arc: start, control and end points (9 floats), world coordinates. */
  curves: Float32Array;
  /** Per arc: 1 if the order was late. */
  late: Uint8Array;
  /** Indices of drawable arcs, all and late only (for the moving lights). */
  allIdx: number[];
  lateIdx: number[];
  /** Merged LineSegments positions for on-time and late arcs. */
  onTimePositions: Float32Array;
  latePositions: Float32Array;
}

/** World position of a seller/customer point (on the X-Z plane). */
function toWorld(lng: number, lat: number): [number, number] {
  const [x, y] = project(lng, lat);
  return [x, -y]; // north is -z
}

/**
 * Build all arc curves from sample rows.
 * Each arc is a quadratic Bezier: start = seller, end = customer, and a
 * control point above the midpoint. The curve's peak is half way between the
 * base and the control point, so control height = 2 x desired peak height.
 * Peak height grows with distance, so long routes arch higher.
 */
export function buildArcs(
  rows: (number | boolean | string)[][],
  col: Record<string, number>,
  maxArcs: number,
): ArcData {
  const n = Math.min(rows.length, maxArcs);
  const curves = new Float32Array(n * 9);
  const late = new Uint8Array(n);
  const allIdx: number[] = [];
  const lateIdx: number[] = [];
  const onTime: number[] = [];
  const lateSeg: number[] = [];

  for (let i = 0; i < n; i++) {
    const r = rows[i];
    const [sx, sz] = toWorld(r[col.seller_lng] as number, r[col.seller_lat] as number);
    const [ex, ez] = toWorld(r[col.customer_lng] as number, r[col.customer_lat] as number);
    const dist = Math.hypot(ex - sx, ez - sz);
    const peak = MIN_HEIGHT + dist * HEIGHT_PER_UNIT;
    const c = [sx, ARC_BASE, sz, (sx + ex) / 2, ARC_BASE + 2 * peak, (sz + ez) / 2, ex, ARC_BASE, ez];
    curves.set(c, i * 9);
    late[i] = r[col.is_late] ? 1 : 0;

    // Seller and customer in the same zip-prefix area: nothing to draw.
    if (dist < 0.01) continue;
    allIdx.push(i);
    if (late[i]) lateIdx.push(i);

    // Sample the curve into ARC_SEGMENTS straight pieces (pairs of points).
    const target = late[i] ? lateSeg : onTime;
    const p = new THREE.Vector3();
    const q = new THREE.Vector3();
    pointOnArc(curves, i, 0, p);
    for (let s = 1; s <= ARC_SEGMENTS; s++) {
      pointOnArc(curves, i, s / ARC_SEGMENTS, q);
      target.push(p.x, p.y, p.z, q.x, q.y, q.z);
      p.copy(q);
    }
  }
  return {
    curves,
    late,
    allIdx,
    lateIdx,
    onTimePositions: new Float32Array(onTime),
    latePositions: new Float32Array(lateSeg),
  };
}

/** Point at t (0..1) on arc i: B(t) = (1-t)^2 P0 + 2(1-t)t C + t^2 P2. */
export function pointOnArc(curves: Float32Array, i: number, t: number, out: THREE.Vector3): THREE.Vector3 {
  const o = i * 9;
  const a = (1 - t) * (1 - t);
  const b = 2 * (1 - t) * t;
  const c = t * t;
  return out.set(
    a * curves[o] + b * curves[o + 3] + c * curves[o + 6],
    a * curves[o + 1] + b * curves[o + 4] + c * curves[o + 7],
    a * curves[o + 2] + b * curves[o + 5] + c * curves[o + 8],
  );
}

/** Straight-line length of arc i on the ground (used to set travel time). */
export function groundLength(curves: Float32Array, i: number): number {
  const o = i * 9;
  return Math.hypot(curves[o + 6] - curves[o], curves[o + 8] - curves[o + 2]);
}
