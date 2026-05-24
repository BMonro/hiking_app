/** Пішохідна маршрутизація: GraphHopper (hike) → OSRM foot → ланцюг сегментів. */

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

async function graphHopperRoute(waypoints: LatLng[]): Promise<LatLng[]> {
  const key = ghKey();
  if (!key) throw new Error("NO_GH_KEY");

  const query = waypoints
    .map((p) => `point=${p.lat},${p.lon}`)
    .join("&");
  const url =
    `${GH_URL}?${query}&vehicle=hike&locale=uk&points_encoded=true&key=${
      encodeURIComponent(key)
    }`;

  const res = await fetch(url, {
    headers: { "User-Agent": "Hikora/1.0 (GraphHopper routing)" },
    signal: AbortSignal.timeout(60000),
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(data?.message ?? "GH_HTTP");
  }
  if (data.message) throw new Error(data.message);

  const paths = data.paths;
  if (!Array.isArray(paths) || paths.length === 0) {
    throw new Error(data.hint ?? "NO_PATH");
  }
  const first = paths[0];
  const pts = first.points;
  if (typeof pts === "string" && pts.length > 0) {
    return decodePolyline(pts);
  }
  if (pts?.coordinates) {
    return lineStringToLatLng(pts.coordinates);
  }
  throw new Error("NO_POINTS");
}

async function osrmFootRoute(waypoints: LatLng[]): Promise<LatLng[]> {
  const coord = waypoints.map((p) => `${p.lon},${p.lat}`).join(";");
  const url = `${OSRM_BASE}/${coord}?overview=full&geometries=geojson`;

  const res = await fetch(url, {
    headers: { "User-Agent": "Hikora/1.0 (OSRM foot fallback)" },
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
  const geom = routes[0]?.geometry;
  if (geom?.coordinates) {
    const pts = lineStringToLatLng(geom.coordinates);
    if (pts.length >= 2) return pts;
  }
  throw new Error("OSRM_NO_GEOM");
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
      } catch (_) { /* fallback */ }
    }
    if (!gotTrail) {
      try {
        const o = await osrmFootRoute([a, b]);
        if (o.length >= 2) {
          seg = o;
          gotTrail = true;
        }
      } catch (_) { /* straight line */ }
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
    } catch (_) { /* OSRM */ }
  }

  try {
    const pts = await osrmFootRoute(waypoints);
    return { points: pts, source: "osrm" };
  } catch (_) { /* chain */ }

  const pts = await chainLegRoutes(waypoints);
  return { points: pts, source: key ? "chain" : "osrm_chain" };
}

export function toGeoJsonLineString(points: LatLng[]): Record<string, unknown> {
  return {
    type: "LineString",
    coordinates: points.map((p) => [p.lon, p.lat]),
  };
}

export function computeRouteStats(
  points: { lat: number; lon: number; altitude_m?: number | null }[],
): { distance_km: number; ascent_m: number; duration_h: number } {
  const coords = points.filter((p) =>
    Number.isFinite(p.lat) && Number.isFinite(p.lon)
  );
  let meters = 0;
  let ascent = 0;
  for (let i = 1; i < coords.length; i++) {
    const prev = coords[i - 1];
    const cur = coords[i];
    meters += haversineM(
      { lat: prev.lat, lon: prev.lon },
      { lat: cur.lat, lon: cur.lon },
    );
    const pa = prev.altitude_m;
    const ca = cur.altitude_m;
    if (pa != null && ca != null) {
      const diff = ca - pa;
      if (diff > 0) ascent += diff;
    }
  }
  const km = meters / 1000;
  const elevationHours = ascent / 600;
  const durationH = km === 0 ? 0 : km / 4 + elevationHours;
  return {
    distance_km: Math.round(km * 100) / 100,
    ascent_m: ascent,
    duration_h: Math.round(durationH * 10) / 10,
  };
}
