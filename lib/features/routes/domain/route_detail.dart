import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'route_model.dart';

class RouteWaypoint {
  final String? name;
  final LatLng position;
  final String pointType;
  final int sortOrder;
  /// Значення `route_points.altitude_m` у БД.
  final int? altitudeM;

  const RouteWaypoint({
    required this.position,
    required this.pointType,
    this.name,
    this.sortOrder = 0,
    this.altitudeM,
  });

  String get typeLabelUk {
    return switch (pointType) {
      'start' => 'Старт',
      'finish' => 'Фініш',
      'peak' => 'Вершина',
      'water' => 'Вода',
      'shelter' => 'Притулок',
      'danger' => 'Небезпека',
      'viewpoint' => 'Огляд',
      _ => pointType,
    };
  }
}

class RouteDetail {
  final RouteModel route;
  final List<RouteWaypoint> waypoints;
  final List<LatLng>? polyline;

  const RouteDetail({
    required this.route,
    required this.waypoints,
    this.polyline,
  });
}

/// Витягує координати лінії з GeoJSON (Feature / LineString / MultiLineString спрощено).
/// Якщо Supabase повертає JSONB як рядок — декодуємо.
List<LatLng>? parseRoutePolylineFromGeoJson(dynamic geojson) {
  if (geojson == null) return null;
  dynamic decoded = geojson;
  if (geojson is String) {
    final s = geojson.trim();
    if (s.isEmpty) return null;
    try {
      decoded = jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
  return _extractLineStringCoords(decoded);
}

List<LatLng>? _extractLineStringCoords(dynamic json) {
  if (json is! Map) return null;
  final type = json['type']?.toString();

  if (type == 'Feature') {
    return _extractLineStringCoords(json['geometry']);
  }
  if (type == 'FeatureCollection') {
    final features = json['features'];
    if (features is List && features.isNotEmpty) {
      return _extractLineStringCoords(features.first);
    }
    return null;
  }
  if (type == 'LineString') {
    final coords = json['coordinates'];
    return _coordsListToLatLng(coords);
  }
  if (type == 'MultiLineString') {
    final coords = json['coordinates'];
    if (coords is List && coords.isNotEmpty && coords.first is List) {
      return _coordsListToLatLng(coords.first);
    }
    return null;
  }
  return null;
}

List<LatLng>? _coordsListToLatLng(dynamic coords) {
  if (coords is! List || coords.isEmpty) return null;
  final out = <LatLng>[];
  for (final c in coords) {
    if (c is List && c.length >= 2) {
      final lon = (c[0] as num).toDouble();
      final lat = (c[1] as num).toDouble();
      out.add(LatLng(lat, lon));
    }
  }
  return out.length >= 2 ? out : null;
}
