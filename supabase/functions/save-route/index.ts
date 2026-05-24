

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import {
  computeRouteStats,
  fetchHikingRouteThrough,
  toGeoJsonLineString,
  type LatLng,
} from "../_shared/routing.ts";

type RoutePointInput = {
  name?: string;
  latitude: number;
  longitude: number;
  altitude_m?: number | null;
  point_type: string;
  sort_order?: number;
};

function hasStartFinish(points: RoutePointInput[]): boolean {
  const start = points.some((p) =>
    p.point_type === "start" && Number.isFinite(p.latitude) &&
    Number.isFinite(p.longitude)
  );
  const finish = points.some((p) =>
    p.point_type === "finish" && Number.isFinite(p.latitude) &&
    Number.isFinite(p.longitude)
  );
  return start && finish;
}

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
    action?: "create" | "update";
    route_id?: string;
    title?: string;
    route_type?: string;
    description?: string;
    difficulty?: string;
    is_public?: boolean;
    points?: RoutePointInput[];
    chosen_route?: {
      geojson?: Record<string, unknown>;
      distance_km?: number;
      duration_h?: number;
      ascent_m?: number;
    };
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const action = body.action;
  if (action !== "create" && action !== "update") {
    return jsonResponse({ error: "invalid_action" }, 400);
  }

  const title = body.title?.trim();
  if (!title) return jsonResponse({ error: "title_required" }, 400);

  const points = (body.points ?? []).filter((p) =>
    Number.isFinite(Number(p.latitude)) && Number.isFinite(Number(p.longitude))
  );
  if (!hasStartFinish(points)) {
    return jsonResponse({ error: "start_finish_required" }, 400);
  }

  const statsInput = points.map((p) => ({
    lat: Number(p.latitude),
    lon: Number(p.longitude),
    altitude_m: p.altitude_m != null ? Number(p.altitude_m) : null,
  }));
  const stats = computeRouteStats(statsInput);
  const chosen = body.chosen_route;

  const waypoints: LatLng[] = statsInput.map((p) => ({ lat: p.lat, lon: p.lon }));
  let geojson: Record<string, unknown> | null = null;
  let distance_km = stats.distance_km;
  let duration_h = stats.duration_h;
  let ascent_m = stats.ascent_m;

  const chosenGeo = chosen?.geojson;
  if (
    chosenGeo &&
    chosenGeo.type === "LineString" &&
    Array.isArray(chosenGeo.coordinates) &&
    (chosenGeo.coordinates as unknown[]).length >= 2
  ) {
    geojson = chosenGeo;
    if (Number.isFinite(Number(chosen?.distance_km))) {
      distance_km = Number(chosen!.distance_km);
    }
    if (Number.isFinite(Number(chosen?.duration_h))) {
      duration_h = Number(chosen!.duration_h);
    }
    if (Number.isFinite(Number(chosen?.ascent_m))) {
      ascent_m = Number(chosen!.ascent_m);
    }
  } else {
    try {
      const { points: poly } = await fetchHikingRouteThrough(waypoints);
      if (poly.length >= 2) {
        geojson = toGeoJsonLineString(poly);
      }
    } catch (_) {
      if (waypoints.length >= 2) {
        geojson = toGeoJsonLineString(waypoints);
      }
    }
  }

  const routePayload = {
    title,
    route_type: body.route_type ?? "linear",
    description: body.description?.trim() ?? "",
    difficulty: body.difficulty ?? "easy",
    distance_km,
    duration_h,
    ascent_m,
    geojson,
  };

  try {
    if (action === "create") {
      const { data: inserted, error } = await supabase
        .from("routes")
        .insert({
          ...routePayload,
          is_public: body.is_public !== false,
          author_id: user.id,
        })
        .select("id")
        .single();
      if (error) throw error;

      const routeId = inserted.id as string;
      const dbPoints = points.map((p, i) => ({
        route_id: routeId,
        name: p.name?.trim() || (p.point_type === "start"
          ? "Старт"
          : p.point_type === "finish"
          ? "Фініш"
          : "Точка"),
        latitude: p.latitude,
        longitude: p.longitude,
        altitude_m: p.altitude_m ?? null,
        point_type: p.point_type,
        sort_order: p.sort_order ?? i,
      }));

      const { error: ptsErr } = await supabase.from("route_points").insert(dbPoints);
      if (ptsErr) throw ptsErr;

      return jsonResponse({ ok: true, route_id: routeId });
    }

    const routeId = body.route_id;
    if (!routeId) return jsonResponse({ error: "route_id_required" }, 400);

    const { data: existing, error: fetchErr } = await supabase
      .from("routes")
      .select("author_id")
      .eq("id", routeId)
      .maybeSingle();
    if (fetchErr || !existing) {
      return jsonResponse({ error: "route_not_found" }, 404);
    }
    if (existing.author_id !== user.id) {
      return jsonResponse({ error: "forbidden" }, 403);
    }

    const updatePayload: Record<string, unknown> = { ...routePayload };
    if (typeof body.is_public === "boolean") {
      updatePayload.is_public = body.is_public;
    }

    const { error: updErr } = await supabase
      .from("routes")
      .update(updatePayload)
      .eq("id", routeId);
    if (updErr) throw updErr;

    await supabase.from("route_points").delete().eq("route_id", routeId);

    const dbPoints = points.map((p, i) => ({
      route_id: routeId,
      name: p.name?.trim() || (p.point_type === "start"
        ? "Старт"
        : p.point_type === "finish"
        ? "Фініш"
        : "Точка"),
      latitude: p.latitude,
      longitude: p.longitude,
      altitude_m: p.altitude_m ?? null,
      point_type: p.point_type,
      sort_order: p.sort_order ?? i,
    }));
    const { error: ptsErr } = await supabase.from("route_points").insert(dbPoints);
    if (ptsErr) throw ptsErr;

    return jsonResponse({ ok: true, route_id: routeId });
  } catch (e) {
    console.error("save-route:", e);
    const msg = e instanceof Error ? e.message : "save_failed";
    return jsonResponse({ error: "save_failed", message: msg }, 500);
  }
});
