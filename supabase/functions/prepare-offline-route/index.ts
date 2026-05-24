

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { fetchHikingRouteThrough, type LatLng } from "../_shared/routing.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  let body: { route_id?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const routeId = body.route_id;
  if (!routeId) return jsonResponse({ error: "route_id_required" }, 400);

  const { data: route, error: routeErr } = await supabase
    .from("routes")
    .select("id, geojson")
    .eq("id", routeId)
    .maybeSingle();
  if (routeErr || !route) {
    return jsonResponse({ error: "route_not_found" }, 404);
  }

  const { data: pointRows, error: ptsErr } = await supabase
    .from("route_points")
    .select("name, latitude, longitude, altitude_m, point_type, sort_order")
    .eq("route_id", routeId)
    .order("sort_order", { ascending: true });
  if (ptsErr) {
    return jsonResponse({ error: "route_points_failed" }, 500);
  }

  const waypoints: LatLng[] = (pointRows ?? []).map((p) => ({
    lat: Number(p.latitude),
    lon: Number(p.longitude),
  })).filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon));

  if (waypoints.length < 2) {
    return jsonResponse({ error: "insufficient_points" }, 400);
  }

  try {
    let polyline: LatLng[] = [];
    let source = "waypoints";

    try {
      const routed = await fetchHikingRouteThrough(waypoints);
      if (routed.points.length >= 2) {
        polyline = routed.points;
        source = routed.source;
      }
    } catch (_) {  }

    if (polyline.length < 2 && route.geojson) {
      const coords = extractGeoJsonCoords(route.geojson);
      if (coords.length >= 2) {
        polyline = coords;
        source = "geojson";
      }
    }

    if (polyline.length < 2) {
      polyline = waypoints;
      source = "waypoints";
    }

    const waypointsOut = (pointRows ?? []).map((p) => ({
      name: p.name,
      lat: Number(p.latitude),
      lon: Number(p.longitude),
      altitude_m: p.altitude_m,
      point_type: p.point_type,
      sort_order: p.sort_order,
    }));

    return jsonResponse({
      ok: true,
      source,
      polyline: polyline.map((p) => ({ lat: p.lat, lon: p.lon })),
      waypoints: waypointsOut,
    });
  } catch (e) {
    console.error("prepare-offline-route:", e);
    return jsonResponse({ error: "prepare_failed" }, 500);
  }
});

function extractGeoJsonCoords(geojson: unknown): LatLng[] {
  let decoded = geojson;
  if (typeof geojson === "string") {
    try {
      decoded = JSON.parse(geojson);
    } catch {
      return [];
    }
  }
  return walkGeoJson(decoded);
}

function walkGeoJson(json: unknown): LatLng[] {
  if (!json || typeof json !== "object") return [];
  const o = json as Record<string, unknown>;
  const type = String(o.type ?? "");

  if (type === "Feature") return walkGeoJson(o.geometry);
  if (type === "FeatureCollection") {
    const features = o.features;
    if (Array.isArray(features) && features.length > 0) {
      return walkGeoJson(features[0]);
    }
    return [];
  }
  if (type === "LineString") {
    const coords = o.coordinates;
    if (!Array.isArray(coords)) return [];
    return coords
      .filter((c) => Array.isArray(c) && c.length >= 2)
      .map((c) => ({ lat: Number(c[1]), lon: Number(c[0]) }))
      .filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon));
  }
  return [];
}
