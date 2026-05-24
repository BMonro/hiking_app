

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { fetchPoisInBounds } from "../_shared/poi.ts";

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

  let body: { south?: number; west?: number; north?: number; east?: number };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const south = Number(body.south);
  const west = Number(body.west);
  const north = Number(body.north);
  const east = Number(body.east);
  if (![south, west, north, east].every(Number.isFinite)) {
    return jsonResponse({ error: "bounds_required" }, 400);
  }

  try {
    const pois = await fetchPoisInBounds(south, west, north, east);
    if (pois === null) {
      return jsonResponse({ ok: true, zoom_too_low: true, pois: [] });
    }
    return jsonResponse({ ok: true, zoom_too_low: false, pois });
  } catch (e) {
    console.error("poi-nearby:", e);
    return jsonResponse({ error: "poi_failed" }, 500);
  }
});
