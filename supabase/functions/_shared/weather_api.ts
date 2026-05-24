

const BASE = "https://api.openweathermap.org/data/2.5";

function owmKey(): string {
  return (Deno.env.get("OPENWEATHER_API_KEY") ?? "").trim();
}

async function owmGet(path: string, params: Record<string, string>): Promise<unknown> {
  const key = owmKey();
  if (!key) throw new Error("OPENWEATHER_API_KEY not configured");

  const url = new URL(`${BASE}${path}`);
  for (const [k, v] of Object.entries(params)) {
    url.searchParams.set(k, v);
  }
  url.searchParams.set("appid", key);
  url.searchParams.set("lang", "uk");
  url.searchParams.set("units", "metric");

  const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(
      (data as Record<string, string>)?.message ?? `OWM HTTP ${res.status}`,
    );
  }
  return data;
}

export async function getWeatherByCity(city: string): Promise<unknown> {
  return owmGet("/weather", { q: city });
}

export async function getWeatherByCoords(lat: number, lon: number): Promise<unknown> {
  return owmGet("/weather", { lat: String(lat), lon: String(lon) });
}

export async function getForecast3h(lat: number, lon: number): Promise<unknown[]> {
  const data = await owmGet("/forecast", {
    lat: String(lat),
    lon: String(lon),
    cnt: "40",
  }) as Record<string, unknown>;
  const list = data.list;
  return Array.isArray(list) ? list as unknown[] : [];
}

export function buildForecastDays(
  items: Record<string, unknown>[],
): { date: string; temp_day: number; temp_night: number; icon: string }[] {
  const byDay = new Map<string, Record<string, unknown>[]>();

  for (const item of items) {
    const dt = Number(item.dt ?? 0) * 1000;
    const d = new Date(dt);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${
      String(d.getDate()).padStart(2, "0")
    }`;
    if (!byDay.has(key)) byDay.set(key, []);
    byDay.get(key)!.push(item);
  }

  const keys = [...byDay.keys()].sort();
  const result: { date: string; temp_day: number; temp_night: number; icon: string }[] = [];

  for (const day of keys) {
    const entries = byDay.get(day)!;
    if (!entries.length) continue;

    let dayMax: number | null = null;
    let nightMin: number | null = null;
    let noonPick: Record<string, unknown> | null = null;
    let bestNoonDiff = 999999;

    for (const e of entries) {
      const main = e.main as Record<string, unknown> | undefined;
      const temp = Number(main?.temp);
      if (!Number.isFinite(temp)) continue;

      const dt = Number(e.dt ?? 0) * 1000;
      const hour = new Date(dt).getHours();
      const isDay = hour >= 9 && hour <= 18;
      const isNight = hour <= 6 || hour >= 21;

      if (isDay) dayMax = dayMax == null ? temp : Math.max(dayMax, temp);
      if (isNight) nightMin = nightMin == null ? temp : Math.min(nightMin, temp);

      const diff = Math.abs(hour - 12);
      if (diff < bestNoonDiff) {
        bestNoonDiff = diff;
        noonPick = e;
      }
    }

    if (dayMax == null || nightMin == null) {
      const temps = entries
        .map((e) => Number((e.main as Record<string, unknown>)?.temp))
        .filter(Number.isFinite);
      if (temps.length) {
        dayMax ??= Math.max(...temps);
        nightMin ??= Math.min(...temps);
      }
    }

    const weatherArr = noonPick?.weather as unknown[] | undefined;
    const icon = (weatherArr?.[0] as Record<string, string>)?.icon ?? "01d";
    if (dayMax == null || nightMin == null) continue;

    result.push({
      date: day,
      temp_day: dayMax,
      temp_night: nightMin,
      icon,
    });
    if (result.length >= 5) break;
  }

  return result;
}
