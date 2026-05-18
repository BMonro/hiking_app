// deploy: npx supabase functions deploy recommend-routes

import { createUserClient } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { AiNotConfiguredError, chatCompletion } from "../_shared/openai.ts";
import { buildProfileContext } from "../_shared/profile.ts";
import { rankRoutesByProfile, type RouteRow } from "../_shared/route_ranking.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const auth = await createUserClient(req);
  if (auth instanceof Response) return auth;
  const { supabase, userId } = auth;

  try {
    const { data: routes, error: routesError } = await supabase
      .from("routes")
      .select(
        "id, title, difficulty, distance_km, duration_h, ascent_m, route_type, description",
      )
      .eq("is_public", true)
      .order("created_at", { ascending: false })
      .limit(40);

    if (routesError) throw routesError;
    if (!routes?.length) {
      return jsonResponse({ recommendations: [], source: "profile" });
    }

    const { data: profile } = await supabase
      .from("profiles")
      .select(
        "fitness_level, preferred_difficulty, preferred_duration_h, experience_count",
      )
      .eq("id", userId)
      .maybeSingle();

    const routeRows = routes as RouteRow[];

    const tryAi = !!Deno.env.get("OPENAI_API_KEY")?.trim();
    if (tryAi) {
      try {
        const profileContext = await buildProfileContext(supabase, userId);
        const catalog = routeRows.map((r) => ({
          id: r.id,
          title: r.title,
          difficulty: r.difficulty,
          distance_km: r.distance_km,
          duration_h: r.duration_h,
          ascent_m: r.ascent_m,
          route_type: r.route_type,
          description: (r.description ?? "").length > 120
            ? `${(r.description ?? "").slice(0, 120)}…`
            : (r.description ?? ""),
        }));

        const system = `Ти експерт з пішохідного туризму в Україні. Обери до 5 маршрутів з каталогу для користувача.
Враховуй рівень підготовки, досвід, бажану складність, тривалість і обмеження здоровʼя.
Відповідай ТІЛЬКИ JSON українською:
{"recommendations":[{"route_id":"uuid","reason":"коротке пояснення до 120 символів"}]}`;

        const user = `Профіль:\n${profileContext}\n\nКаталог:\n${
          JSON.stringify(catalog)
        }`;

        const raw = await chatCompletion(
          [
            { role: "system", content: system },
            { role: "user", content: user },
          ],
          { jsonMode: true },
        );

        const parsed = JSON.parse(raw) as {
          recommendations?: Array<{ route_id?: string; reason?: string }>;
        };
        const recommendations = (parsed.recommendations ?? [])
          .filter((item) => item.route_id && item.reason)
          .slice(0, 5)
          .map((item) => ({
            route_id: item.route_id!,
            reason: item.reason!,
          }));

        if (recommendations.length > 0) {
          return jsonResponse({ recommendations, source: "ai" });
        }
      } catch (e) {
        if (!(e instanceof AiNotConfiguredError)) {
          console.error("recommend-routes AI fallback:", e);
        }
      }
    }

    const recommendations = rankRoutesByProfile(profile, routeRows, 5);
    return jsonResponse({ recommendations, source: "profile" });
  } catch (e) {
    console.error("recommend-routes error:", e);
    return jsonResponse({ error: "recommend_failed" }, 500);
  }
});
