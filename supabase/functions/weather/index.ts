// deploy: npx supabase functions deploy weather
// body: { action: current|forecast|route|city, lat?, lon?, city?, route_id? }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import {
  buildForecastDays,
  getForecast3h,
  getWeatherByCity,
  getWeatherByCoords,
} from "../_shared/weather_api.ts";

type Action = "current" | "forecast" | "both" | "route" | "city";

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
    action?: Action;
    lat?: number;
    lon?: number;
    city?: string;
    route_id?: string;
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const action = body.action ?? "current";

  try {
    if (action === "city") {
      const city = body.city?.trim();
      if (!city) return jsonResponse({ error: "city_required" }, 400);
      const current = await getWeatherByCity(city);
      return jsonResponse({ ok: true, current });
    }

    if (action === "route") {
      const routeId = body.route_id;
      if (!routeId) return jsonResponse({ error: "route_id_required" }, 400);

      const { data: route, error: routeErr } = await supabase
        .from("routes")
        .select("title")
        .eq("id", routeId)
        .maybeSingle();
      if (routeErr || !route) {
        return jsonResponse({ error: "route_not_found" }, 404);
      }

      const { data: points, error: ptsErr } = await supabase
        .from("route_points")
        .select("name, latitude, longitude, point_type, sort_order")
        .eq("route_id", routeId)
        .order("sort_order", { ascending: true });
      if (ptsErr) {
        return jsonResponse({ error: "route_points_failed" }, 500);
      }

      const rows = await Promise.all(
        (points ?? []).map(async (p) => {
          const lat = Number(p.latitude);
          const lon = Number(p.longitude);
          const weather = await getWeatherByCoords(lat, lon);
          const label = (p.name as string)?.trim() ||
            String(p.point_type ?? "point");
          return { label, weather };
        }),
      );

      return jsonResponse({
        ok: true,
        route_title: route.title,
        points: rows,
      });
    }

    const lat = Number(body.lat);
    const lon = Number(body.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
      return jsonResponse({ error: "lat_lon_required" }, 400);
    }

    if (action === "current") {
      const current = await getWeatherByCoords(lat, lon);
      return jsonResponse({ ok: true, current });
    }

    if (action === "forecast") {
      const items = await getForecast3h(lat, lon) as Record<string, unknown>[];
      const forecast = buildForecastDays(items);
      return jsonResponse({ ok: true, forecast });
    }

    if (action === "both") {
      const [current, items] = await Promise.all([
        getWeatherByCoords(lat, lon),
        getForecast3h(lat, lon),
      ]);
      const forecast = buildForecastDays(items as Record<string, unknown>[]);
      return jsonResponse({ ok: true, current, forecast });
    }

    return jsonResponse({ error: "unknown_action" }, 400);
  } catch (e) {
    console.error("weather:", e);
    const msg = e instanceof Error ? e.message : "weather_failed";
    if (msg.includes("OPENWEATHER")) {
      return jsonResponse({ error: "weather_not_configured", message: msg }, 503);
    }
    return jsonResponse({ error: "weather_failed", message: msg }, 500);
  }
});
