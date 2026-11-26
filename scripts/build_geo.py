#!/usr/bin/env python3
"""
build_geo.py: Brazil state outlines for the hero map, from IBGE municipal
boundaries.

Source (CC0 1.0, data from IBGE):
  https://github.com/tbrugz/geodata-br  file geojson/geojs-100-mun.json
  and that repo's README.md, which lists each state's code, UF and name.

Steps
  1. Group the 5,564 municipalities by state (first 2 digits of the IBGE id).
  2. Dissolve each state: a border segment shared by two municipalities
     appears twice and is dropped; the segments left (count 1) form the state
     outline. They are chained back into closed rings.
  3. Classify rings: the largest is the outer boundary; a ring inside another
     ring is a hole (e.g. Goias around the Federal District); others are
     islands.
  4. Simplify each ring with Douglas-Peucker and round to 3 decimals
     (about 100 m) to keep the file small.

Usage (run from the repo root):
  python3 -I scripts/build_geo.py <geojs-100-mun.json> <README.md> site/public/geo/brazil-states.json

Standard library only.
"""
import json
import re
import sys
from collections import defaultdict

TOLERANCE_DEG = 0.02     # Douglas-Peucker tolerance (~2 km), invisible at map scale
DECIMALS = 3             # output precision (~100 m)
MATCH_DECIMALS = 6       # precision used to match shared vertices between municipalities
SOURCE = {
    "name": "IBGE municipal boundaries via tbrugz/geodata-br",
    "url": "https://github.com/tbrugz/geodata-br",
    "license": "CC0-1.0",
    "original_data": "IBGE (Instituto Brasileiro de Geografia e Estatistica)",
}


def parse_states(readme_text):
    """'* AC / Acre - [geojson/geojs-12-mun.json]' -> {'12': ('AC', 'Acre')}"""
    states = {}
    for uf, name, code in re.findall(r"^\* ([A-Z]{2}) / (.+?)\s+- \[geojson/geojs-(\d{2})-mun\.json\]", readme_text, re.M):
        states[code] = (uf, name.strip())
    return states


def key(pt):
    return (round(pt[0], MATCH_DECIMALS), round(pt[1], MATCH_DECIMALS))


def dissolve(polygons):
    """Outline of a set of polygons that share vertices along common borders."""
    count = defaultdict(int)
    directed = []
    for rings in polygons:
        for ring in rings:
            pts = [key(p) for p in ring]
            if pts[0] != pts[-1]:
                pts.append(pts[0])
            for a, b in zip(pts, pts[1:]):
                if a == b:
                    continue
                count[frozenset((a, b))] += 1
                directed.append((a, b))
    # keep segments used once: they are on the outside of the state
    outside = [(a, b) for a, b in directed if count[frozenset((a, b))] == 1]
    nxt = defaultdict(list)
    for a, b in outside:
        nxt[a].append(b)
    rings = []
    while nxt:
        start = next(iter(nxt))
        ring = [start]
        cur = start
        while True:
            options = nxt.get(cur)
            if not options:
                break
            nb = options.pop()
            if not options:
                del nxt[cur]
            ring.append(nb)
            cur = nb
            if cur == start:
                break
        if len(ring) >= 4 and ring[0] == ring[-1]:
            rings.append(ring)
    return rings


def area(ring):
    return 0.5 * sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(ring, ring[1:]))


def inside(pt, ring):
    x, y = pt
    hit = False
    for (x1, y1), (x2, y2) in zip(ring, ring[1:]):
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            hit = not hit
    return hit


def simplify(points, tol):
    """Douglas-Peucker on an open polyline (iterative, so deep rings don't recurse)."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        i, j = stack.pop()
        (x1, y1), (x2, y2) = points[i], points[j]
        dx, dy = x2 - x1, y2 - y1
        norm = (dx * dx + dy * dy) ** 0.5 or 1e-12
        best, best_d = None, tol
        for k in range(i + 1, j):
            x0, y0 = points[k]
            d = abs(dy * x0 - dx * y0 + x2 * y1 - y2 * x1) / norm
            if d > best_d:
                best, best_d = k, d
        if best is not None:
            keep[best] = True
            stack += [(i, best), (best, j)]
    return [p for p, k in zip(points, keep) if k]


def simplify_ring(ring):
    # split the closed ring in two halves so the endpoints are not pinned together
    mid = len(ring) // 2
    a = simplify(ring[: mid + 1], TOLERANCE_DEG)
    b = simplify(ring[mid:], TOLERANCE_DEG)
    out = [(round(x, DECIMALS), round(y, DECIMALS)) for x, y in a[:-1] + b]
    dedup = [out[0]]
    for p in out[1:]:
        if p != dedup[-1]:
            dedup.append(p)
    if dedup[0] != dedup[-1]:
        dedup.append(dedup[0])
    return dedup if len(dedup) >= 4 else None


def main(mun_path, readme_path, out_path):
    states = parse_states(open(readme_path, encoding="utf-8").read())
    mun = json.load(open(mun_path, encoding="utf-8"))
    by_state = defaultdict(list)
    for f in mun["features"]:
        g = f["geometry"]
        polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
        by_state[str(f["properties"]["id"])[:2]].extend(polys)

    features, report = [], []
    for code in sorted(by_state):
        uf, name = states[code]
        rings = sorted(dissolve(by_state[code]), key=lambda r: abs(area(r)), reverse=True)
        outers, holes = [], defaultdict(list)
        for r in rings:
            parent = next((i for i, o in enumerate(outers) if inside(r[0], o)), None)
            if parent is None:
                outers.append(r)
            else:
                holes[parent].append(r)
        polygons = []
        for i, o in enumerate(outers):
            so = simplify_ring(o)
            if not so:
                continue  # islands smaller than the tolerance disappear
            polygons.append([so] + [h for h in (simplify_ring(x) for x in holes[i]) if h])
        features.append({
            "type": "Feature",
            "properties": {"code": code, "uf": uf, "name": name},
            "geometry": {"type": "MultiPolygon", "coordinates": polygons},
        })
        report.append(f"{uf}: {len(rings)} rings -> {len(polygons)} polygons, "
                      f"{sum(len(r) for p in polygons for r in p)} points")

    out = {"type": "FeatureCollection", "source": SOURCE, "features": features}
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print("\n".join(report))
    print(f"{len(features)} states written to {out_path}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
