export type RouteRow = {
  id: string;
  title: string;
  difficulty: string;
  distance_km: number;
  duration_h: number;
  ascent_m: number;
  route_type?: string;
  description?: string;
};

export type ProfileRow = {
  fitness_level?: string;
  preferred_difficulty?: string;
  preferred_duration_h?: number;
  experience_count?: number;
};

export function rankRoutesByProfile(
  profile: ProfileRow | null,
  routes: RouteRow[],
  limit = 5,
): Array<{ route_id: string; reason: string }> {
  if (!routes.length) return [];

  const fitness = profile?.fitness_level ?? "beginner";
  const prefDiff = profile?.preferred_difficulty;
  const prefDuration = profile?.preferred_duration_h;
  const experience = profile?.experience_count ?? 0;
  const targetDiff = prefDiff ?? difficultyFromFitness(fitness);

  const scored: Array<{ route: RouteRow; score: number; reason: string }> = [];

  for (const route of routes) {
    let score = 0;
    const parts: string[] = [];

    const diffScore = difficultyScore(targetDiff, route.difficulty);
    score += diffScore * 40;
    if (diffScore > 0.7) parts.push("відповідає вашій складності");

    if (prefDuration && prefDuration > 0 && route.duration_h > 0) {
      const ratio = route.duration_h / prefDuration;
      if (ratio <= 1.15) {
        score += 25;
        parts.push("комфортна тривалість");
      } else if (ratio <= 1.4) {
        score += 10;
      } else {
        score -= 15;
      }
    }

    if (experience < 3 && route.difficulty === "easy") {
      score += 15;
      parts.push("підходить для набору досвіду");
    } else if (experience >= 10 && route.difficulty === "hard") {
      score += 10;
      parts.push("цікавий виклик для досвідченого");
    }

    if (route.ascent_m > 0 && route.ascent_m <= 600 && fitness === "beginner") {
      score += 8;
    }

    const reason = parts.length
      ? capitalize(parts.join(", "))
      : "Збалансований варіант для вашого профілю";

    scored.push({ route, score, reason });
  }

  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, limit).map((e) => ({
    route_id: e.route.id,
    reason: e.reason,
  }));
}

function difficultyFromFitness(fitness: string): string {
  if (fitness === "advanced") return "hard";
  if (fitness === "intermediate") return "medium";
  return "easy";
}

function difficultyScore(target: string, actual: string): number {
  const order = ["easy", "medium", "hard"];
  const ti = order.indexOf(target);
  const ai = order.indexOf(actual);
  if (ti < 0 || ai < 0) return 0.5;
  const diff = Math.abs(ai - ti);
  if (diff === 0) return 1;
  if (diff === 1) return 0.65;
  return 0.25;
}

function capitalize(s: string): string {
  if (!s) return s;
  return s[0].toUpperCase() + s.slice(1);
}
