// deploy: npx supabase functions deploy route-hike
// body: { waypoints?: [{lat, lon}], route_id?: string }

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

  let body: {
    waypoints?: { lat: number; lon: number }[];
    route_id?: string;
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  let waypoints: LatLng[] = [];

  if (body.route_id) {
    const { data: rows, error } = await supabase
      .from("route_points")
      .select("latitude, longitude")
      .eq("route_id", body.route_id)
      .order("sort_order", { ascending: true });
    if (error) {
      return jsonResponse({ error: "route_points_failed", message: error.message }, 500);
    }
    waypoints = (rows ?? []).map((r) => ({
      lat: Number(r.latitude),
      lon: Number(r.longitude),
    })).filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon));
  } else if (Array.isArray(body.waypoints)) {
    waypoints = body.waypoints
      .map((p) => ({ lat: Number(p.lat), lon: Number(p.lon) }))
      .filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon));
  }

  if (waypoints.length < 2) {
    return jsonResponse({ error: "need_at_least_two_waypoints" }, 400);
  }

  try {
    const { points, source } = await fetchHikingRouteThrough(waypoints);
    return jsonResponse({
      ok: true,
      source,
      points: points.map((p) => ({ lat: p.lat, lon: p.lon })),
    });
  } catch (e) {
    console.error("route-hike:", e);
    const msg = e instanceof Error ? e.message : "routing_failed";
    return jsonResponse({ error: "routing_failed", message: msg }, 500);
  }
});
