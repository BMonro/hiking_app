

export type MapPoiDto = {
  lat: number;
  lon: number;
  kind: string;
  name?: string | null;
  elevation_m?: number | null;
};

const OVERPASS_URL = "https://overpass-api.de/api/interpreter";

function kindFromTags(tags: Record<string, string>): string {
  if (tags.natural === "peak") return "peak";
  if (tags.natural === "spring" || tags.natural === "hot_spring") return "water";
  if (tags.amenity === "drinking_water" || tags.amenity === "fountain") {
    return "water";
  }
  if (tags.amenity === "shelter") return "shelter";
  if (tags.man_made === "water_well") return "water";
  const tourism = tags.tourism ?? "";
  if (tourism === "picnic_site") return "picnicSite";
  if (tourism === "camp_site" || tourism === "caravan_site") return "campSite";
  if (tourism === "alpine_hut" || tourism === "wilderness_hut") return "hut";
  if (tourism === "viewpoint") return "viewpoint";
  if (
    ["attraction", "museum", "gallery", "artwork", "zoo", "theme_park"].includes(
      tourism,
    )
  ) return "attraction";
  if (tourism === "information") return "information";
  const historic = tags.historic ?? "";
  if (historic && historic !== "yes") return "historic";
  return "other";
}

function elevationFromTags(tags: Record<string, string>): number | null {
  const raw = tags.ele?.trim();
  if (!raw) return null;
  const first = raw.split(/\s+/)[0];
  return parseInt(first, 10) || null;
}

export async function fetchPoisInBounds(
  south: number,
  west: number,
  north: number,
  east: number,
): Promise<MapPoiDto[] | null> {
  const latSpan = Math.abs(north - south);
  const lonSpan = Math.abs(east - west);
  if (latSpan > 0.65 || lonSpan > 1.0) return null;

  const query = `
[out:json][timeout:55];
(
  node["tourism"="alpine_hut"](${south},${west},${north},${east});
  node["tourism"="wilderness_hut"](${south},${west},${north},${east});
  node["tourism"="attraction"](${south},${west},${north},${east});
  node["tourism"="museum"](${south},${west},${north},${east});
  node["tourism"="gallery"](${south},${west},${north},${east});
  node["tourism"="artwork"](${south},${west},${north},${east});
  node["tourism"="zoo"](${south},${west},${north},${east});
  node["tourism"="theme_park"](${south},${west},${north},${east});
  node["tourism"="viewpoint"](${south},${west},${north},${east});
  node["tourism"="information"](${south},${west},${north},${east});
  node["tourism"="picnic_site"](${south},${west},${north},${east});
  node["tourism"="camp_site"](${south},${west},${north},${east});
  node["tourism"="caravan_site"](${south},${west},${north},${east});
  node["amenity"="shelter"](${south},${west},${north},${east});
  node["amenity"="drinking_water"](${south},${west},${north},${east});
  node["amenity"="fountain"](${south},${west},${north},${east});
  node["natural"="peak"](${south},${west},${north},${east});
  node["natural"="spring"](${south},${west},${north},${east});
  node["natural"="hot_spring"](${south},${west},${north},${east});
  node["man_made"="water_well"](${south},${west},${north},${east});
  node["historic"="castle"](${south},${west},${north},${east});
  node["historic"="ruins"](${south},${west},${north},${east});
  node["historic"="archaeological_site"](${south},${west},${north},${east});
  node["historic"="monument"](${south},${west},${north},${east});
  node["historic"="memorial"](${south},${west},${north},${east});
  node["historic"="wayside_shrine"](${south},${west},${north},${east});
  node["historic"="battlefield"](${south},${west},${north},${east});
  node["historic"="fort"](${south},${west},${north},${east});
  node["historic"="city_gate"](${south},${west},${north},${east});
  node["historic"="manor"](${south},${west},${north},${east});
  way["tourism"="alpine_hut"](${south},${west},${north},${east});
  way["tourism"="wilderness_hut"](${south},${west},${north},${east});
  way["amenity"="shelter"](${south},${west},${north},${east});
  way["natural"="peak"](${south},${west},${north},${east});
  way["tourism"="museum"](${south},${west},${north},${east});
  way["tourism"="picnic_site"](${south},${west},${north},${east});
  way["tourism"="camp_site"](${south},${west},${north},${east});
  way["tourism"="caravan_site"](${south},${west},${north},${east});
  way["historic"="castle"](${south},${west},${north},${east});
  way["historic"="ruins"](${south},${west},${north},${east});
  way["historic"="archaeological_site"](${south},${west},${north},${east});
  way["historic"="monument"](${south},${west},${north},${east});
);
out center;
`;

  const res = await fetch(OVERPASS_URL, {
    method: "POST",
    headers: {
      "Content-Type": "text/plain",
      "User-Agent": "Hikora/1.0 (Flutter; tourism POI preview)",
    },
    body: query,
    signal: AbortSignal.timeout(45000),
  });
  const data = await res.json();
  const elements = data.elements;
  if (!Array.isArray(elements)) return [];

  const list: MapPoiDto[] = [];
  for (const raw of elements) {
    if (!raw || typeof raw !== "object") continue;
    const e = raw as Record<string, unknown>;
    let lat: number | undefined;
    let lon: number | undefined;
    const type = String(e.type ?? "");
    if (type === "node") {
      lat = Number(e.lat);
      lon = Number(e.lon);
    } else if (type === "way" || type === "relation") {
      const c = e.center as Record<string, unknown> | undefined;
      if (c) {
        lat = Number(c.lat);
        lon = Number(c.lon);
      }
    }
    if (lat == null || lon == null || !Number.isFinite(lat) || !Number.isFinite(lon)) {
      continue;
    }
    const tagsRaw = e.tags as Record<string, string> | undefined;
    const tags: Record<string, string> = {};
    if (tagsRaw) {
      for (const [k, v] of Object.entries(tagsRaw)) {
        tags[k] = String(v ?? "");
      }
    }
    const name = tags.name?.trim();
    list.push({
      lat,
      lon,
      kind: kindFromTags(tags),
      name: name || null,
      elevation_m: elevationFromTags(tags),
    });
  }
  return list;
}
