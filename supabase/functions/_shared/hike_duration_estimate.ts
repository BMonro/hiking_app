

export type HikeSegmentInput = {
  distance_m: number;
  delta_alt_m?: number | null;
};

export type HikeDurationResult = {
  distance_km: number;
  ascent_m: number;
  descent_m: number;
  duration_h: number;
};

const FLAT_SPEED_KMH = 4.0;
const ASCENT_MIN_PER_100M = 10.0;
const DESCENT_MIN_GENTLE = 4.0;
const DESCENT_MIN_STEEP = 9.0;
const STEEP_GRADE_PERCENT = 18;
const FATIGUE_EFFORT_THRESHOLD = 8;
const MAX_FATIGUE = 1.35;

function fatigueMultiplier(cumulativeKm: number, cumulativeAscentM: number): number {
  const effort = cumulativeKm + cumulativeAscentM / 400;
  if (effort <= FATIGUE_EFFORT_THRESHOLD) return 1;
  const excess = effort - FATIGUE_EFFORT_THRESHOLD;
  return Math.min(MAX_FATIGUE, 1 + 0.028 * excess);
}

function segmentHours(distKm: number, deltaAltM: number | null | undefined): number {
  if (distKm <= 0) {
    if (deltaAltM == null || deltaAltM === 0) return 0;
    const climb = Math.abs(deltaAltM);
    const minPer100 = deltaAltM > 0 ? ASCENT_MIN_PER_100M : DESCENT_MIN_STEEP;
    return (climb / 100) * (minPer100 / 60);
  }

  const flatH = distKm / FLAT_SPEED_KMH;
  const delta = deltaAltM ?? 0;

  if (delta > 0) {
    const ascentH = (delta / 100) * (ASCENT_MIN_PER_100M / 60);
    const grade = (delta / (distKm * 1000)) * 100;
    const steepFactor = grade > 25 ? 1.18 : grade > 15 ? 1.1 : 1;
    return (flatH + ascentH) * steepFactor;
  }

  if (delta < 0) {
    const loss = -delta;
    const grade = (loss / (distKm * 1000)) * 100;
    const minPer100 = grade >= STEEP_GRADE_PERCENT
      ? DESCENT_MIN_STEEP
      : DESCENT_MIN_GENTLE;
    const descentH = (loss / 100) * (minPer100 / 60);
    const downhillFlatH = distKm / 3.3;
    return Math.max(flatH, downhillFlatH) + descentH;
  }

  return flatH;
}

function distanceOnlyWithFatigue(km: number): number {
  let hours = 0;
  let walked = 0;
  const stepKm = 0.5;
  while (walked < km) {
    const chunk = Math.min(stepKm, km - walked);
    hours += (chunk / FLAT_SPEED_KMH) * fatigueMultiplier(walked, 0);
    walked += chunk;
  }
  return hours;
}

export function estimateHikeDurationFromSegments(
  segments: HikeSegmentInput[],
): HikeDurationResult {
  let totalMeters = 0;
  let ascent = 0;
  let descent = 0;
  let totalHours = 0;
  let cumulativeKm = 0;
  let cumulativeAscent = 0;
  let hadAltitude = false;

  for (const seg of segments) {
    const distKm = seg.distance_m / 1000;
    if (distKm <= 0 && (seg.delta_alt_m ?? 0) === 0) continue;

    totalMeters += seg.distance_m;
    const delta = seg.delta_alt_m;
    if (delta != null) {
      hadAltitude = true;
      if (delta > 0) ascent += delta;
      if (delta < 0) descent += -delta;
    }

    const fatigue = fatigueMultiplier(cumulativeKm, cumulativeAscent);
    totalHours += segmentHours(distKm, delta) * fatigue;
    cumulativeKm += distKm;
    if (delta != null && delta > 0) cumulativeAscent += delta;
  }

  const km = totalMeters / 1000;
  if (km === 0) {
    return { distance_km: 0, ascent_m: 0, descent_m: 0, duration_h: 0 };
  }

  if (!hadAltitude) {
    totalHours = distanceOnlyWithFatigue(km);
  }

  return {
    distance_km: Math.round(km * 100) / 100,
    ascent_m: ascent,
    descent_m: descent,
    duration_h: Math.round(totalHours * 10) / 10,
  };
}

export function estimateHikeDurationFromPoints(
  points: { lat: number; lon: number; altitude_m?: number | null }[],
  haversineM: (a: { lat: number; lon: number }, b: { lat: number; lon: number }) => number,
): HikeDurationResult {
  const coords = points.filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon));
  const segments: HikeSegmentInput[] = [];
  for (let i = 1; i < coords.length; i++) {
    const prev = coords[i - 1];
    const cur = coords[i];
    const distance_m = haversineM(
      { lat: prev.lat, lon: prev.lon },
      { lat: cur.lat, lon: cur.lon },
    );
    let delta_alt_m: number | null = null;
    const pa = prev.altitude_m;
    const ca = cur.altitude_m;
    if (pa != null && ca != null) delta_alt_m = ca - pa;
    segments.push({ distance_m, delta_alt_m });
  }
  return estimateHikeDurationFromSegments(segments);
}
