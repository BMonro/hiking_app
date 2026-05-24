import 'package:latlong2/latlong.dart';

class RouteVariant {
  const RouteVariant({
    required this.difficulty,
    required this.difficultyLabel,
    required this.distanceKm,
    required this.durationH,
    required this.ascentM,
    required this.points,
  });

  final String difficulty;
  final String difficultyLabel;
  final double distanceKm;
  final double durationH;
  final int ascentM;
  final List<LatLng> points;

  Map<String, dynamic> toGeoJsonLineString() => {
        'type': 'LineString',
        'coordinates': points.map((p) => [p.longitude, p.latitude]).toList(),
      };

  Map<String, dynamic> toChosenRoutePayload() => {
        'geojson': toGeoJsonLineString(),
        'distance_km': distanceKm,
        'duration_h': durationH,
        'ascent_m': ascentM,
      };

  factory RouteVariant.fromJson(Map<String, dynamic> json) {
    final ptsRaw = json['points'] as List? ?? [];
    final points = <LatLng>[];
    for (final p in ptsRaw) {
      if (p is! Map) continue;
      final lat = (p['lat'] as num?)?.toDouble();
      final lon = (p['lon'] as num?)?.toDouble();
      if (lat != null && lon != null) points.add(LatLng(lat, lon));
    }
    return RouteVariant(
      difficulty: json['difficulty']?.toString() ?? 'medium',
      difficultyLabel: json['difficulty_label']?.toString() ?? 'Середній',
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      durationH: (json['duration_h'] as num?)?.toDouble() ?? 0,
      ascentM: (json['ascent_m'] as num?)?.round() ?? 0,
      points: points,
    );
  }
}
