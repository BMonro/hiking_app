

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
  lines.push(`Завершених походів (журнал): ${profile?.experience_count ?? 0}`);
  if (profile?.preferred_difficulty) {
    const d = profile.preferred_difficulty.toString();
    lines.push(`Бажана складність: ${difficultyLabels[d] ?? d}`);
  }
  if (profile?.preferred_duration_h != null) {
    lines.push(`Бажана тривалість: ${profile.preferred_duration_h} год`);
  }
  const cond = (conditions ?? []).map((c) => c.condition).filter(Boolean);
  if (cond.length) lines.push(`Обмеження здоровʼя: ${cond.join(", ")}`);
  const bio = profile?.bio?.toString().trim();
  if (bio) lines.push(`Про себе: ${bio}`);
  lines.push(
    `Статистика: ${stats?.total_hikes ?? 0} походів, ${stats?.total_distance_km ?? 0} км, ${stats?.total_ascent_m ?? 0} м висоти.`,
  );
  return lines.join("\n");
}

async function chatCompletion(
  messages: Array<{ role: string; content: string }>,
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
    body: JSON.stringify({ model, messages, temperature: 0.6 }),
  });
  if (!res.ok) throw new Error(await res.text());
  const data = await res.json();
  return data?.choices?.[0]?.message?.content?.trim() ?? "";
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

  let body: { ping?: boolean; messages?: Array<{ role: string; content: string }> };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  if (body.ping) {
    if (!Deno.env.get("OPENAI_API_KEY")?.trim()) {
      return json({ error: "ai_not_configured" }, 503);
    }
    return json({ ok: true });
  }

  const messages = (body.messages ?? [])
    .filter((m) =>
      (m.role === "user" || m.role === "assistant") && m.content?.trim()
    )
    .slice(-20)
    .map((m) => ({ role: m.role, content: m.content.trim() }));

  if (!messages.length) return json({ error: "messages_required" }, 400);

  try {
    const profileContext = await buildProfileContext(supabase, user.id);
    const system = `Ти дружній україномовний порадник з пішохідного туризму в HikingApp.
Давай практичні поради. Враховуй профіль. Не вигадуй GPS-координати.
Якщо питання про медицину — до лікаря. До 6 речень українською.

Профіль:
${profileContext}`;
    const reply = await chatCompletion([
      { role: "system", content: system },
      ...messages,
    ]);
    return json({ reply });
  } catch (e) {
    if (String(e).includes("AI_NOT_CONFIGURED")) {
      return json({ error: "ai_not_configured" }, 503);
    }
    console.error(e);
    return json({ error: "ai_request_failed" }, 502);
  }
});
