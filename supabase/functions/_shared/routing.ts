

import { estimateHikeDurationFromPoints } from "./hike_duration_estimate.ts";

export type LatLng = { lat: number; lon: number };

const GH_URL = "https://graphhopper.com/api/1/route";
const OSRM_BASE =
  "https://routing.openstreetmap.de/routed-foot/route/v1/foot";

function ghKey(): string {
  return (Deno.env.get("GRAPHOPPER_API_KEY") ?? "").trim();
}

function decodePolyline(encoded: string): LatLng[] {
  const poly: LatLng[] = [];
  let index = 0;
  const len = encoded.length;
  let lat = 0;
  let lng = 0;

  while (index < len) {
    let result = 0;
    let shift = 0;
    let b: number;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    const dlat = (result & 1) !== 0 ? ~(result >> 1) : result >> 1;
    lat += dlat;

    result = 0;
    shift = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    const dlng = (result & 1) !== 0 ? ~(result >> 1) : result >> 1;
    lng += dlng;

    poly.push({ lat: lat / 1e5, lon: lng / 1e5 });
  }
  return poly;
}

function lineStringToLatLng(coords: unknown[]): LatLng[] {
  const out: LatLng[] = [];
  for (const c of coords) {
    if (Array.isArray(c) && c.length >= 2) {
      const a = Number(c[0]);
      const b = Number(c[1]);
      out.push({ lat: b, lon: a });
    }
  }
  return out;
}

function haversineM(a: LatLng, b: LatLng): number {
  const R = 6371000;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLon = ((b.lon - a.lon) * Math.PI) / 180;
  const lat1 = (a.lat * Math.PI) / 180;
  const lat2 = (b.lat * Math.PI) / 180;
  const x =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(x));
}

function appendSegment(out: LatLng[], seg: LatLng[]): void {
  if (seg.length === 0) return;
  if (out.length === 0) {
    out.push(...seg);
    return;
  }
  const gap = haversineM(out[out.length - 1], seg[0]);
  if (gap < 5) {
    out.push(...seg.slice(1));
  } else {
    out.push(...seg);
  }
}

type ParsedGhPath = {
  points: LatLng[];
  distance_m: number;
  time_ms: number;
  ascent_m: number;
};

function parseGhPath(path: Record<string, unknown>): ParsedGhPath | null {
  const pts = path.points;
  let points: LatLng[] = [];
  if (typeof pts === "string" && pts.length > 0) {
    points = decodePolyline(pts);
  } else if (
    pts && typeof pts === "object" &&
    Array.isArray((pts as { coordinates?: unknown }).coordinates)
  ) {
    points = lineStringToLatLng(
      (pts as { coordinates: unknown[] }).coordinates,
    );
  }
  if (points.length < 2) return null;

  const distance_m = Number(path.distance) || 0;
  const time_ms = Number(path.time) || 0;
  const rawAsc = path.ascend ?? path.ascent ?? path.ascend_m;
  const ascent_m = Math.max(0, Math.round(Number(rawAsc) || 0));

  return { points, distance_m, time_ms, ascent_m };
}

async function fetchGraphHopperPaths(
  waypoints: LatLng[],
  extraQuery = "",
): Promise<ParsedGhPath[]> {
  const key = ghKey();
  if (!key) throw new Error("NO_GH_KEY");

  const query = waypoints
    .map((p) => `point=${p.lat},${p.lon}`)
    .join("&");
  const url =
    `${GH_URL}?${query}&vehicle=hike&locale=uk&points_encoded=true&key=${
      encodeURIComponent(key)
    }${extraQuery}`;

  const res = await fetch(url, {
    headers: { "User-Agent": "Hikora/1.0 (GraphHopper routing)" },
    signal: AbortSignal.timeout(90000),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data?.message ?? "GH_HTTP");
  if (data.message) throw new Error(data.message);

  const paths = data.paths;
  if (!Array.isArray(paths) || paths.length === 0) {
    throw new Error(data.hint ?? "NO_PATH");
  }

  const parsed: ParsedGhPath[] = [];
  for (const raw of paths) {
    if (!raw || typeof raw !== "object") continue;
    const p = parseGhPath(raw as Record<string, unknown>);
    if (p) parsed.push(p);
  }
  return parsed;
}

async function graphHopperRouteParsed(
  waypoints: LatLng[],
  extraQuery = "",
): Promise<ParsedGhPath> {
  const paths = await fetchGraphHopperPaths(waypoints, extraQuery);
  if (paths.length === 0) throw new Error("NO_POINTS");
  return paths[0];
}

async function graphHopperRoute(waypoints: LatLng[]): Promise<LatLng[]> {
  const path = await graphHopperRouteParsed(waypoints);
  return path.points;
}

function parseOsrmRoute(route: Record<string, unknown>): ParsedGhPath | null {
  const geom = route.geometry as { coordinates?: unknown[] } | undefined;
  if (!geom?.coordinates) return null;
  const points = lineStringToLatLng(geom.coordinates);
  if (points.length < 2) return null;
  const distance_m = Number(route.distance) || 0;
  const durationSec = Number(route.duration) || 0;
  return {
    points,
    distance_m,
    time_ms: Math.round(durationSec * 1000),
    ascent_m: 0,
  };
}

async function osrmFootPaths(
  waypoints: LatLng[],
  { alternatives = false }: { alternatives?: boolean } = {},
): Promise<ParsedGhPath[]> {
  const coord = waypoints.map((p) => `${p.lon},${p.lat}`).join(";");
  let url =
    `${OSRM_BASE}/${coord}?overview=full&geometries=geojson&steps=false`;
  if (alternatives && waypoints.length === 2) {
    url += "&alternatives=3";
  }

  const res = await fetch(url, {
    headers: { "User-Agent": "Hikora/1.0 (OSRM foot)" },
    signal: AbortSignal.timeout(60000),
  });
  const data = await res.json();
  if (data.code && data.code !== "Ok") {
    throw new Error(data.message ?? data.code);
  }
  const routes = data.routes;
  if (!Array.isArray(routes) || routes.length === 0) {
    throw new Error("OSRM_NO_ROUTES");
  }
  const parsed: ParsedGhPath[] = [];
  for (const raw of routes) {
    if (!raw || typeof raw !== "object") continue;
    const p = parseOsrmRoute(raw as Record<string, unknown>);
    if (p) parsed.push(p);
  }
  return parsed;
}

async function osrmFootRoute(waypoints: LatLng[]): Promise<LatLng[]> {
  const paths = await osrmFootPaths(waypoints);
  if (paths.length === 0) throw new Error("OSRM_NO_GEOM");
  return paths[0].points;
}

async function chainLegRoutes(waypoints: LatLng[]): Promise<LatLng[]> {
  const out: LatLng[] = [];
  const key = ghKey();

  for (let i = 0; i < waypoints.length - 1; i++) {
    const a = waypoints[i];
    const b = waypoints[i + 1];
    let seg: LatLng[] = [a, b];
    let gotTrail = false;

    if (key) {
      try {
        const g = await graphHopperRoute([a, b]);
        if (g.length >= 2) {
          seg = g;
          gotTrail = true;
        }
      } catch (_) {  }
    }
    if (!gotTrail) {
      try {
        const o = await osrmFootRoute([a, b]);
        if (o.length >= 2) {
          seg = o;
          gotTrail = true;
        }
      } catch (_) {  }
    }
    appendSegment(out, seg);
  }
  return out;
}

export async function fetchHikingRouteThrough(
  waypoints: LatLng[],
): Promise<{ points: LatLng[]; source: string }> {
  if (waypoints.length < 2) {
    return { points: [], source: "none" };
  }

  const key = ghKey();
  if (key) {
    try {
      const pts = await graphHopperRoute(waypoints);
      return { points: pts, source: "graphhopper" };
    } catch (_) {  }
  }

  try {
    const pts = await osrmFootRoute(waypoints);
    return { points: pts, source: "osrm" };
  } catch (_) {  }

  const pts = await chainLegRoutes(waypoints);
  return { points: pts, source: key ? "chain" : "osrm_chain" };
}

export function toGeoJsonLineString(points: LatLng[]): Record<string, unknown> {
  return {
    type: "LineString",
    coordinates: points.map((p) => [p.lon, p.lat]),
  };
}

export type RouteVariantResult = {
  difficulty: "easy" | "medium" | "hard";
  difficulty_label: string;
  distance_km: number;
  duration_h: number;
  ascent_m: number;
  points: LatLng[];
};

function statsFromGhPath(p: ParsedGhPath): {
  distance_km: number;
  duration_h: number;
  ascent_m: number;
} {
  const distance_km = Math.round((p.distance_m / 1000) * 100) / 100;
  let duration_h = 0;
  let duration_h = 0;
  if (distance_km > 0) {
    const modeled = estimateHikeDurationFromPoints(
      p.points.map((pt) => ({ lat: pt.lat, lon: pt.lon })),
      haversineM,
    );
    duration_h = modeled.duration_h;
    const extraAscent = Math.max(0, p.ascent_m - modeled.ascent_m);
    if (extraAscent > 0) {
      duration_h += (extraAscent / 100) * (10 / 60) * 1.08;
    }
  }
  if (p.time_ms > 0) {
    const ghHours = p.time_ms / 3_600_000;
    duration_h = Math.max(duration_h, ghHours);
  }
  duration_h = Math.round(duration_h * 10) / 10;
  return { distance_km, duration_h, ascent_m: p.ascent_m };
}

function effortScore(stats: {
  distance_km: number;
  ascent_m: number;
  duration_h: number;
}): number {
  return stats.ascent_m * 2 + stats.distance_km * 10 + stats.duration_h * 5;
}

function difficultyLabelUk(d: "easy" | "medium" | "hard"): string {
  if (d === "easy") return "Легкий";
  if (d === "hard") return "Важкий";
  return "Середній";
}

function classifyAbsolute(stats: {
  distance_km: number;
  ascent_m: number;
  duration_h: number;
}): "easy" | "medium" | "hard" {
  const e = effortScore(stats);
  if (e < 90) return "easy";
  if (e > 170) return "hard";
  return "medium";
}

function assignDifficultyLabels(
  items: { stats: ReturnType<typeof statsFromGhPath>; points: LatLng[] }[],
): RouteVariantResult[] {
  const sorted = [...items].sort(
    (a, b) => effortScore(a.stats) - effortScore(b.stats),
  );
  const n = sorted.length;
  let labels: ("easy" | "medium" | "hard")[];

  if (n === 1) {
    labels = [classifyAbsolute(sorted[0].stats)];
  } else if (n === 2) {
    const ratio = effortScore(sorted[1].stats) /
      Math.max(effortScore(sorted[0].stats), 1);
    labels = ratio < 1.12 ? ["easy", "medium"] : ["easy", "hard"];
  } else {
    labels = ["easy", "medium", "hard"];
    if (n > 3) {
      labels = sorted.map((_, i) => {
        const t = i / (n - 1);
        if (t < 0.34) return "easy" as const;
        if (t < 0.67) return "medium" as const;
        return "hard" as const;
      });
    }
  }

  return sorted.map((item, i) => {
    const d = labels[Math.min(i, labels.length - 1)];
    return {
      difficulty: d,
      difficulty_label: difficultyLabelUk(d),
      distance_km: item.stats.distance_km,
      duration_h: item.stats.duration_h,
      ascent_m: item.stats.ascent_m,
      points: item.points,
    };
  });
}

function minDistToPolylineM(p: LatLng, poly: LatLng[]): number {
  let min = Infinity;
  for (const q of poly) {
    const d = haversineM(p, q);
    if (d < min) min = d;
  }
  return min;
}

function pathsAreSimilar(a: ParsedGhPath, b: ParsedGhPath): boolean {
  const lenRatio = Math.abs(a.distance_m - b.distance_m) /
    Math.max(a.distance_m, b.distance_m, 1);
  if (lenRatio > 0.12) return false;

  const midA = a.points[Math.floor(a.points.length / 2)];
  const midB = b.points[Math.floor(b.points.length / 2)];
  if (haversineM(midA, midB) > 500) return false;

  const samples = 5;
  let sum = 0;
  for (let i = 0; i < samples; i++) {
    const idx = Math.floor(
      ((a.points.length - 1) * i) / Math.max(samples - 1, 1),
    );
    sum += minDistToPolylineM(a.points[idx], b.points);
  }
  return sum / samples < 250;
}

function dedupeParsedPaths(paths: ParsedGhPath[]): ParsedGhPath[] {
  const out: ParsedGhPath[] = [];
  for (const p of paths) {
    if (!out.some((o) => pathsAreSimilar(o, p))) out.push(p);
  }
  return out;
}

function buildViaCandidates(a: LatLng, b: LatLng): LatLng[] {
  const distM = haversineM(a, b);
  const scale = Math.min(2.5, Math.max(1, distM / 6000));
  const offsetsKm = [0.8, 2, 4, 7, -0.8, -2, -4, -7].map((k) => k * scale);
  const dLat = b.lat - a.lat;
  const dLon = b.lon - a.lon;
  const len = Math.hypot(dLat, dLon) || 1e-9;
  const pLat = -dLon / len;
  const pLon = dLat / len;

  const out: LatLng[] = [];
  for (const frac of [0.3, 0.5, 0.7]) {
    const midLat = a.lat + dLat * frac;
    const midLon = a.lon + dLon * frac;
    const lonScale = 111320 * Math.cos((midLat * Math.PI) / 180);
    for (const km of offsetsKm) {
      out.push({
        lat: midLat + (pLat * km * 1000) / 111320,
        lon: midLon + (pLon * km * 1000) / lonScale,
      });
    }
  }
  return out;
}

async function graphHopperAlternativePaths(
  waypoints: LatLng[],
): Promise<ParsedGhPath[]> {
  const alt =
    "&algorithm=alternative_route&alternative_route.max_paths=3" +
    "&alternative_route.max_weight_factor=2.2" +
    "&alternative_route.max_share_factor=0.8" +
    "&ch.disable=true";
  return await fetchGraphHopperPaths(waypoints, alt);
}

async function discoverVariantsViaWaypoints(
  a: LatLng,
  b: LatLng,
  existing: ParsedGhPath[],
  fetch: (wps: LatLng[]) => Promise<ParsedGhPath>,
): Promise<ParsedGhPath[]> {
  const found: ParsedGhPath[] = [];
  const candidates = buildViaCandidates(a, b);

  const settled = await Promise.allSettled(
    candidates.map((via) => fetch([a, via, b])),
  );

  for (const result of settled) {
    if (existing.length + found.length >= 3) break;
    if (result.status !== "fulfilled") continue;
    const path = result.value;
    const pool = [...existing, ...found];
    if (!pool.some((o) => pathsAreSimilar(o, path))) {
      found.push(path);
    }
  }
  return found;
}

async function collectRouteVariants(
  waypoints: LatLng[],
): Promise<{ paths: ParsedGhPath[]; source: string }> {
  const collected: ParsedGhPath[] = [];

  try {
    const alt = await graphHopperAlternativePaths(waypoints);
    collected.push(...alt);
  } catch (_) {  }

  try {
    const direct = await graphHopperRouteParsed(waypoints);
    if (!collected.some((p) => pathsAreSimilar(p, direct))) {
      collected.push(direct);
    }
  } catch (_) {  }

  let deduped = dedupeParsedPaths(collected);

  if (deduped.length < 3 && waypoints.length === 2) {
    const extra = await discoverVariantsViaWaypoints(
      waypoints[0],
      waypoints[1],
      deduped,
      graphHopperRouteParsed,
    );
    deduped = dedupeParsedPaths([...deduped, ...extra]);
  }

  const source = deduped.length > 1
    ? (collected.length > 1 ? "graphhopper_alternatives" : "graphhopper_via")
    : "graphhopper";

  return { paths: deduped.slice(0, 3), source };
}

async function collectOsrmVariants(
  waypoints: LatLng[],
  existing: ParsedGhPath[],
): Promise<ParsedGhPath[]> {
  const collected = [...existing];

  try {
    const alt = await osrmFootPaths(waypoints, { alternatives: true });
    for (const p of alt) {
      if (!collected.some((o) => pathsAreSimilar(o, p))) collected.push(p);
    }
  } catch (_) {  }

  if (collected.length < 3) {
    try {
      const direct = (await osrmFootPaths(waypoints))[0];
      if (direct && !collected.some((o) => pathsAreSimilar(o, direct))) {
        collected.push(direct);
      }
    } catch (_) {  }
  }

  let deduped = dedupeParsedPaths(collected);

  if (deduped.length < 3 && waypoints.length === 2) {
    const fetchOsrm = async (wps: LatLng[]) => {
      const list = await osrmFootPaths(wps);
      if (list.length === 0) throw new Error("OSRM_EMPTY");
      return list[0];
    };
    const extra = await discoverVariantsViaWaypoints(
      waypoints[0],
      waypoints[1],
      deduped,
      fetchOsrm,
    );
    deduped = dedupeParsedPaths([...deduped, ...extra]);
  }

  return deduped.slice(0, 3);
}

function pathsToVariants(
  paths: ParsedGhPath[],
  source: string,
): { variants: RouteVariantResult[]; source: string } {
  const items = paths.map((p) => ({
    stats: statsFromGhPath(p),
    points: p.points,
  }));
  return {
    variants: assignDifficultyLabels(items),
    source,
  };
}

export async function fetchHikingRouteVariants(
  waypoints: LatLng[],
): Promise<{ variants: RouteVariantResult[]; source: string }> {
  if (waypoints.length < 2) {
    return { variants: [], source: "none" };
  }

  let paths: ParsedGhPath[] = [];
  let source = "none";

  if (ghKey()) {
    try {
      const gh = await collectRouteVariants(waypoints);
      paths = gh.paths;
      source = gh.source;
    } catch (e) {
      console.warn("graphhopper variants:", e);
    }
  }

  if (paths.length < 3) {
    const before = paths.length;
    paths = await collectOsrmVariants(waypoints, paths);
    if (paths.length > before) {
      source = source === "none" ? "osrm" : `${source}+osrm`;
    }
  }

  if (paths.length > 0) {
    return pathsToVariants(paths, source);
  }

  const { points } = await fetchHikingRouteThrough(waypoints);
  if (points.length < 2) {
    return { variants: [], source: "none" };
  }

  let distance_m = 0;
  for (let i = 1; i < points.length; i++) {
    distance_m += haversineM(points[i - 1], points[i]);
  }
  const stats = statsFromGhPath({
    points,
    distance_m,
    time_ms: 0,
    ascent_m: 0,
  });
  const d = classifyAbsolute(stats);
  return {
    variants: [{
      difficulty: d,
      difficulty_label: difficultyLabelUk(d),
      distance_km: stats.distance_km,
      duration_h: stats.duration_h,
      ascent_m: stats.ascent_m,
      points,
    }],
    source: "fallback",
  };
}

export function computeRouteStats(
  points: { lat: number; lon: number; altitude_m?: number | null }[],
): { distance_km: number; ascent_m: number; duration_h: number } {
  const est = estimateHikeDurationFromPoints(points, haversineM);
  return {
    distance_km: est.distance_km,
    ascent_m: est.ascent_m,
    duration_h: est.duration_h,
  };
}
