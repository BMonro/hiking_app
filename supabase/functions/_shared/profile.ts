import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

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

export async function buildProfileContext(
  supabase: SupabaseClient,
  userId: string,
): Promise<string> {
  const { data: profile } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", userId)
    .maybeSingle();

  const { data: conditions } = await supabase
    .from("profile_health_conditions")
    .select("condition")
    .eq("user_id", userId);

  const { data: stats } = await supabase
    .from("profile_stats")
    .select("*")
    .eq("user_id", userId)
    .maybeSingle();

  const lines: string[] = [];
  const name = profile?.full_name?.toString().trim();
  if (name) lines.push(`Імʼя: ${name}`);
  if (profile?.age != null) lines.push(`Вік: ${profile.age}`);
  const fitness = profile?.fitness_level?.toString() ?? "beginner";
  lines.push(
    `Рівень підготовки: ${fitnessLabels[fitness] ?? fitness}`,
  );
  lines.push(
    `Завершених походів (журнал): ${profile?.experience_count ?? 0}`,
  );
  if (profile?.preferred_difficulty) {
    const d = profile.preferred_difficulty.toString();
    lines.push(
      `Бажана складність маршрутів: ${difficultyLabels[d] ?? d}`,
    );
  }
  if (profile?.preferred_duration_h != null) {
    lines.push(`Бажана тривалість: ${profile.preferred_duration_h} год`);
  }
  const conditionList = (conditions ?? [])
    .map((c) => c.condition?.toString())
    .filter((c): c is string => !!c && c.length > 0);
  if (conditionList.length > 0) {
    lines.push(`Обмеження здоровʼя: ${conditionList.join(", ")}`);
  }
  const bio = profile?.bio?.toString().trim();
  if (bio) lines.push(`Про себе: ${bio}`);
  lines.push(
    `Статистика: ${stats?.total_hikes ?? 0} походів, ${
      stats?.total_distance_km ?? 0
    } км, ${stats?.total_ascent_m ?? 0} м набору висоти.`,
  );

  return lines.join("\n");
}
