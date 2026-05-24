

export type PlaceResult = {
  display_name: string;
  primary_label: string;
  lat: number;
  lon: number;
  elevation_m?: number | null;
  is_peak: boolean;
};

const UA =
  "hikora/1.0 (Supabase Edge; OSM geosearch; +https://openstreetmap.org/copyright)";

const UKR_VIEWBOX = { south: 44, west: 22, north: 52.5, east: 41 };

const cyrillicRe = /[\u0400-\u04FF\u0490-\u052F]/;

function hasCyrillic(s: string): boolean {
  return cyrillicRe.test(s);
}

function pickUkrainianName(tags: Record<string, string>): string | null {
  const keys = [
    "name:uk",
    "official_name:uk",
    "alt_name:uk",
    "name",
    "official_name",
    "alt_name",
  ];
  let fallback: string | null = null;
  for (const key of keys) {
    const v = tags[key]?.trim();
    if (!v) continue;
    if (hasCyrillic(v)) return v;
    fallback ??= v;
  }
  return fallback;
}

function dedupeKey(lat: number, lon: number): string {
  return `${Math.round(lat * 10000)}_${Math.round(lon * 10000)}`;
}

function sortUkrainianFirst(list: PlaceResult[]): PlaceResult[] {
  return [...list].sort((a, b) => {
    const ua = (hasCyrillic(b.primary_label) ? 1 : 0) -
      (hasCyrillic(a.primary_label) ? 1 : 0);
    if (ua !== 0) return ua;
    return a.primary_label.localeCompare(b.primary_label);
  });
}

function mergePlaces(a: PlaceResult[], b: PlaceResult[], maxItems = 14): PlaceResult[] {
  const merged = new Map<string, PlaceResult>();
  for (const r of [...a, ...b]) {
    if (r.lat === 0 && r.lon === 0) continue;
    const k = dedupeKey(r.lat, r.lon);
    const existing = merged.get(k);
    if (!existing) {
      merged.set(k, r);
    } else {
      const keepUa = hasCyrillic(existing.primary_label);
      const otherUa = hasCyrillic(r.primary_label);
      if (!keepUa && otherUa) merged.set(k, r);
    }
  }
  return sortUkrainianFirst([...merged.values()]).slice(0, maxItems);
}

function mergePreferPeaks(
  peaks: PlaceResult[],
  places: PlaceResult[],
  maxItems = 15,
): PlaceResult[] {
  const merged = new Map<string, PlaceResult>();
  for (const p of peaks) merged.set(dedupeKey(p.lat, p.lon), p);
  for (const n of places) {
    const k = dedupeKey(n.lat, n.lon);
    if (!merged.has(k)) merged.set(k, n);
  }
  return [...merged.values()]
    .sort((a, b) => {
      const pk = (b.is_peak ? 1 : 0) - (a.is_peak ? 1 : 0);
      if (pk !== 0) return pk;
      const ua = (hasCyrillic(b.primary_label) ? 1 : 0) -
        (hasCyrillic(a.primary_label) ? 1 : 0);
      if (ua !== 0) return ua;
      return a.primary_label.localeCompare(b.primary_label);
    })
    .slice(0, maxItems);
}

function fromNominatimJson(json: Record<string, unknown>): PlaceResult {
  const lat = parseFloat(String(json.lat ?? "0"));
  const lon = parseFloat(String(json.lon ?? "0"));
  const displayName = String(json.display_name ?? "").trim();
  const cls = String(json.class ?? "");
  const typ = String(json.type ?? "");
  const isPeak = cls === "natural" &&
    ["peak", "volcano", "ridge", "saddle"].includes(typ);

  const tagMaps: Record<string, string>[] = [];
  for (const key of ["namedetails", "extratags"]) {
    const raw = json[key];
    if (raw && typeof raw === "object") {
      tagMaps.push(raw as Record<string, string>);
    }
  }

  let primary = String(json.name ?? "").trim();
  for (const tags of tagMaps) {
    const fromTags = pickUkrainianName(tags);
    if (fromTags) {
      primary = fromTags;
      break;
    }
  }
  if (!primary) primary = displayName.split(",")[0]?.trim() ?? "";

  let ele: number | null = null;
  const extratags = json.extratags as Record<string, unknown> | undefined;
  if (extratags?.ele != null) {
    ele = parseInt(String(extratags.ele).replace(/[^\d-]/g, ""), 10) || null;
  }

  return {
    display_name: displayName || primary,
    primary_label: primary,
    lat,
    lon,
    elevation_m: ele,
    is_peak: isPeak,
  };
}

function fromPhotonFeature(feature: Record<string, unknown>): PlaceResult {
  const geom = feature.geometry as Record<string, unknown> | undefined;
  const props = feature.properties as Record<string, string> | undefined;
  if (!geom || !props) {
    return { display_name: "", primary_label: "", lat: 0, lon: 0, is_peak: false };
  }
  const coords = geom.coordinates as number[] | undefined;
  if (!coords || coords.length < 2) {
    return { display_name: "", primary_label: "", lat: 0, lon: 0, is_peak: false };
  }
  const lon = Number(coords[0]);
  const lat = Number(coords[1]);
  const isPeak = props.osm_key === "natural" &&
    ["peak", "volcano", "ridge"].includes(props.osm_value ?? "");

  let primary = pickUkrainianName(props) ?? "";
  if (!primary) {
    for (const key of ["city", "town", "village", "hamlet", "locality", "state"]) {
      const v = props[key]?.trim();
      if (v) {
        primary = v;
        break;
      }
    }
  }
  if (!primary) primary = "Місце";

  const parts = [props.city, props.state, props.country].filter(Boolean);
  let display = parts.length ? `${primary} · ${parts.join(", ")}` : primary;
  if (hasCyrillic(primary)) {
    display = display.replace(/Ukraine/g, "Україна");
  }

  return {
    display_name: display,
    primary_label: primary,
    lat,
    lon,
    is_peak: isPeak,
  };
}

function fromOverpassElement(el: Record<string, unknown>): PlaceResult {
  let lat: number | undefined;
  let lon: number | undefined;
  const type = String(el.type ?? "");
  if (type === "node") {
    lat = Number(el.lat);
    lon = Number(el.lon);
  } else {
    const c = el.center as Record<string, unknown> | undefined;
    if (c) {
      lat = Number(c.lat);
      lon = Number(c.lon);
    }
  }
  const tags = (el.tags ?? {}) as Record<string, string>;
  const name = pickUkrainianName(tags) ?? "Вершина";
  const eleRaw = tags.ele;
  const ele = eleRaw
    ? parseInt(String(eleRaw).replace(/[^\d-]/g, ""), 10) || null
    : null;
  const region = tags.nat_name ?? tags["addr:region"] ?? tags.is_in ??
    tags["addr:country"];
  let display = name;
  if (ele != null) display += ` · ${ele} м`;
  if (region) display += ` — ${region}`;

  return {
    display_name: display,
    primary_label: name,
    lat: lat ?? 0,
    lon: lon ?? 0,
    elevation_m: ele,
    is_peak: true,
  };
}

async function photonSearch(q: string, limit: number): Promise<PlaceResult[]> {
  const vb = UKR_VIEWBOX;
  const url = new URL("https://photon.komoot.io/api/");
  url.searchParams.set("q", q);
  url.searchParams.set("limit", String(limit));
  url.searchParams.set("bbox", `${vb.west},${vb.south},${vb.east},${vb.north}`);

  const res = await fetch(url, {
    headers: { "User-Agent": UA, "Accept-Language": "uk,en;q=0.9" },
    signal: AbortSignal.timeout(5000),
  });
  const data = await res.json();
  const features = data.features;
  if (!Array.isArray(features)) return [];

  const out: PlaceResult[] = [];
  for (const f of features) {
    if (!f || typeof f !== "object") continue;
    const r = fromPhotonFeature(f as Record<string, unknown>);
    if (r.lat !== 0 || r.lon !== 0) out.push(r);
  }
  return out;
}

async function nominatimSearch(
  q: string,
  limit: number,
  restrict: boolean,
): Promise<PlaceResult[]> {
  const vb = UKR_VIEWBOX;
  const url = new URL("https://nominatim.openstreetmap.org/search");
  url.searchParams.set("q", q);
  url.searchParams.set("format", "json");
  url.searchParams.set("limit", String(limit));
  url.searchParams.set("addressdetails", "1");
  url.searchParams.set("extratags", "1");
  url.searchParams.set("namedetails", "1");
  url.searchParams.set("countrycodes", "ua");
  url.searchParams.set(
    "viewbox",
    `${vb.west},${vb.north},${vb.east},${vb.south}`,
  );
  if (restrict) url.searchParams.set("bounded", "1");

  const res = await fetch(url, {
    headers: { "User-Agent": UA, "Accept-Language": "uk,en;q=0.9" },
    signal: AbortSignal.timeout(8000),
  });
  const data = await res.json();
  if (!Array.isArray(data)) return [];
  return data.map((e) => fromNominatimJson(e as Record<string, unknown>));
}

async function overpassPeaks(q: string, limit: number, timeoutSec: number): Promise<PlaceResult[]> {
  const safe = q.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
  if (safe.length < 3) return [];
  const vb = UKR_VIEWBOX;
  const body = `
[out:json][timeout:${timeoutSec}];
(
  node["natural"="peak"]["name"~"${safe}",i](${vb.south},${vb.west},${vb.north},${vb.east});
  way["natural"="peak"]["name"~"${safe}",i](${vb.south},${vb.west},${vb.north},${vb.east});
);
out center tags ${limit};
`;

  const res = await fetch("https://overpass-api.de/api/interpreter", {
    method: "POST",
    headers: {
      "User-Agent": UA,
      "Content-Type": "text/plain",
    },
    body,
    signal: AbortSignal.timeout((timeoutSec + 5) * 1000),
  });
  const data = await res.json();
  const elements = data.elements;
  if (!Array.isArray(elements)) return [];

  const out: PlaceResult[] = [];
  for (const e of elements) {
    if (!e || typeof e !== "object") continue;
    const r = fromOverpassElement(e as Record<string, unknown>);
    if (r.lat !== 0 || r.lon !== 0) out.push(r);
  }
  return sortUkrainianFirst(out);
}

async function searchPlaces(q: string): Promise<PlaceResult[]> {
  const [photon, nominatim] = await Promise.all([
    photonSearch(q, 12).catch(() => [] as PlaceResult[]),
    nominatimSearch(q, 12, false).catch(() => [] as PlaceResult[]),
  ]);
  let list = mergePlaces(nominatim, photon, 14);
  if (list.length === 0) {
    list = await nominatimSearch(q, 12, false).catch(() => []);
  }
  return sortUkrainianFirst(list);
}

export type GeosearchMode =
  | "route_full"
  | "weather_full"
  | "weather_places"
  | "weather_peaks"
  | "route_places"
  | "route_peaks";

export async function geosearch(
  query: string,
  mode: GeosearchMode,
): Promise<PlaceResult[]> {
  const q = query.trim();
  if (q.length < 3) return [];

  switch (mode) {
    case "weather_places":
      return searchPlaces(q);
    case "weather_peaks":
      return overpassPeaks(q, 12, 8);
    case "weather_full": {
      const [places, peaks] = await Promise.all([
        searchPlaces(q),
        overpassPeaks(q, 12, 8).catch(() => []),
      ]);
      return mergePreferPeaks(peaks, places, 18);
    }
    case "route_places":
      return searchPlaces(q);
    case "route_peaks":
      return overpassPeaks(q, 15, 10);
    case "route_full": {
      const [places, peaks] = await Promise.all([
        searchPlaces(q),
        overpassPeaks(q, 15, 10).catch(() => []),
      ]);
      return mergePreferPeaks(peaks, places, 18);
    }
    default:
      return [];
  }
}
