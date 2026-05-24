

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { geosearch, type GeosearchMode } from "../_shared/geosearch.ts";

const MODES = new Set<string>([
  "route_full",
  "weather_full",
  "weather_places",
  "weather_peaks",
  "route_places",
  "route_peaks",
]);

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

  let body: { query?: string; mode?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const query = body.query?.trim() ?? "";
  const mode = body.mode ?? "route_full";
  if (!MODES.has(mode)) {
    return jsonResponse({ error: "invalid_mode" }, 400);
  }

  try {
    const results = await geosearch(query, mode as GeosearchMode);
    return jsonResponse({ ok: true, results });
  } catch (e) {
    console.error("geosearch:", e);
    return jsonResponse({ error: "geosearch_failed" }, 500);
  }
});
