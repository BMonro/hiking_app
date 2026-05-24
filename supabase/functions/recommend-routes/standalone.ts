

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function buildProfileContext(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<string> {
  const fitnessLabels: Record<string, string> = {
    beginner: "початківець",
    intermediate: "середній",
    advanced: "досвідчений",
  };
  const difficultyLabels: Record<string, string> = {
    easy: "легкий",
    medium: "середній",
    hard: "важкий",
  };
  const { data: profile } = await supabase.from("profiles").select("*").eq(
    "id",
    userId,
  ).maybeSingle();
  const { data: conditions } = await supabase.from("profile_health_conditions")
    .select("condition").eq("user_id", userId);
  const { data: stats } = await supabase.from("profile_stats").select("*").eq(
    "user_id",
    userId,
  ).maybeSingle();
  const lines: string[] = [];
  const name = profile?.full_name?.toString().trim();
  if (name) lines.push(`Імʼя: ${name}`);
  if (profile?.age != null) lines.push(`Вік: ${profile.age}`);
  const fitness = profile?.fitness_level?.toString() ?? "beginner";
  lines.push(`Рівень підготовки: ${fitnessLabels[fitness] ?? fitness}`);
  lines.push(`Завершених походів: ${profile?.experience_count ?? 0}`);
  if (profile?.preferred_difficulty) {
    const d = profile.preferred_difficulty.toString();
    lines.push(`Бажана складність: ${difficultyLabels[d] ?? d}`);
  }
  if (profile?.preferred_duration_h != null) {
    lines.push(`Тривалість: ${profile.preferred_duration_h} год`);
  }
  const cond = (conditions ?? []).map((c) => c.condition).filter(Boolean);
  if (cond.length) lines.push(`Здоровʼя: ${cond.join(", ")}`);
  const bio = profile?.bio?.toString().trim();
  if (bio) lines.push(`Про себе: ${bio}`);
  lines.push(
    `Статистика: ${stats?.total_hikes ?? 0} походів, ${stats?.total_distance_km ?? 0} км, ${stats?.total_ascent_m ?? 0} м.`,
  );
  return lines.join("\n");
}

async function chatCompletionJson(
  system: string,
  user: string,
): Promise<string> {
  const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim();
  if (!apiKey) throw new Error("AI_NOT_CONFIGURED");
  const baseUrl = Deno.env.get("OPENAI_BASE_URL")?.trim() ||
    "https://api.openai.com/v1";
  const model = Deno.env.get("OPENAI_MODEL")?.trim() || "gpt-4o-mini";
  const res = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
      temperature: 0.6,
      response_format: { type: "json_object" },
    }),
  });
  if (!res.ok) throw new Error(await res.text());
  const data = await res.json();
  return data?.choices?.[0]?.message?.content?.trim() ?? "{}";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return json({ error: "unauthorized" }, 401);
  }
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return json({ error: "unauthorized" }, 401);

  try {
    const { data: routes, error } = await supabase
      .from("routes")
      .select(
        "id, title, difficulty, distance_km, duration_h, ascent_m, route_type, description",
      )
      .eq("is_public", true)
      .order("created_at", { ascending: false })
      .limit(40);
    if (error) throw error;
    if (!routes?.length) return json({ recommendations: [] });

    const profileContext = await buildProfileContext(supabase, user.id);
    const catalog = routes.map((r) => ({
      id: r.id,
      title: r.title,
      difficulty: r.difficulty,
      distance_km: r.distance_km,
      duration_h: r.duration_h,
      ascent_m: r.ascent_m,
      route_type: r.route_type,
      description: ((r.description ?? "") as string).slice(0, 120),
    }));

    const system = `Обери до 5 маршрутів для користувача з каталогу. Українською. Тільки JSON:
{"recommendations":[{"route_id":"uuid","reason":"до 120 символів"}]}`;
    const userPrompt = `Профіль:\n${profileContext}\n\nКаталог:\n${
      JSON.stringify(catalog)
    }`;

    const raw = await chatCompletionJson(system, userPrompt);
    let parsed: { recommendations?: Array<{ route_id?: string; reason?: string }> };
    try {
      parsed = JSON.parse(raw);
    } catch {
      return json({ recommendations: [] });
    }
    const recommendations = (parsed.recommendations ?? [])
      .filter((x) => x.route_id && x.reason)
      .slice(0, 5)
      .map((x) => ({ route_id: x.route_id!, reason: x.reason! }));

    return json({ recommendations });
  } catch (e) {
    if (String(e).includes("AI_NOT_CONFIGURED")) {
      return json({ error: "ai_not_configured" }, 503);
    }
    console.error(e);
    return json({ error: "ai_request_failed" }, 502);
  }
});
