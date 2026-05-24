import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/backend_api.dart';
import '../../../core/config/routing_config.dart'
    show GraphHopperConfig, OsrmConfig;

class RoutingRepository {
  RoutingRepository({Dio? dio, BackendApi? api})
      : _dio = dio ?? Dio(),
        _api = api ?? BackendApi();

  final Dio _dio;
  final BackendApi _api;

  Future<List<LatLng>> fetchHikingRoute(LatLng from, LatLng to) =>
      fetchHikingRouteThrough([from, to]);

  Future<List<LatLng>> fetchHikingRouteThrough(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return const [];

    try {
      final data = await _api.invoke(
        'route-hike',
        body: {
          'waypoints': waypoints
              .map((p) => {'lat': p.latitude, 'lon': p.longitude})
              .toList(),
        },
        timeout: const Duration(seconds: 90),
      );
      return _parseEdgePoints(data['points']);
    } on BackendApiException {
      rethrow;
    } catch (_) {
      return _fetchHikingRouteLocal(waypoints);
    }
  }

  Future<List<LatLng>> fetchHikingRouteForRouteId(String routeId) async {
    try {
      final data = await _api.invoke(
        'route-hike',
        body: {'route_id': routeId},
        timeout: const Duration(seconds: 90),
      );
      return _parseEdgePoints(data['points']);
    } catch (_) {
      return const [];
    }
  }

  List<LatLng> _parseEdgePoints(dynamic raw) {
    if (raw is! List) return const [];
    final out = <LatLng>[];
    for (final p in raw) {
      if (p is! Map) continue;
      final lat = (p['lat'] as num?)?.toDouble();
      final lon = (p['lon'] as num?)?.toDouble();
      if (lat != null && lon != null) out.add(LatLng(lat, lon));
    }
    return out;
  }

  Future<List<LatLng>> _fetchHikingRouteLocal(List<LatLng> waypoints) async {
    final key = GraphHopperConfig.apiKey.trim();
    if (key.isNotEmpty) {
      try {
        return await _graphHopperRouteVia(waypoints);
      } catch (_) {}
    }
    try {
      return await _osrmFootRouteVia(waypoints);
    } catch (_) {}
    return _chainLegRoutes(waypoints);
  }

  Future<List<LatLng>> _graphHopperRouteVia(List<LatLng> waypoints) async {
    final key = GraphHopperConfig.apiKey.trim();
    final query = StringBuffer();
    for (var i = 0; i < waypoints.length; i++) {
      final p = waypoints[i];
      if (i > 0) query.write('&');
      query.write('point=${p.latitude},${p.longitude}');
    }
    query.write('&vehicle=hike&locale=uk&points_encoded=true');
    query.write('&key=${Uri.encodeQueryComponent(key)}');

    final url = '${GraphHopperConfig.routeUrl}?${query.toString()}';
    final response = await _dio.get<Map<String, dynamic>>(
      url,
      options: Options(
        receiveTimeout: const Duration(seconds: 60),
        headers: {'User-Agent': 'HikingApp/1.0 (GraphHopper routing)'},
      ),
    );

    final data = response.data;
    if (data == null) throw StateError('EMPTY_RESPONSE');
    final message = data['message']?.toString();
    if (message != null && message.isNotEmpty) throw StateError(message);

    final paths = data['paths'];
    if (paths is! List || paths.isEmpty) {
      throw StateError(data['hint']?.toString() ?? 'NO_PATH');
    }
    final first = paths.first;
    if (first is! Map<String, dynamic>) throw StateError('BAD_PATH');

    final pts = first['points'];
    if (pts is String && pts.isNotEmpty) return _decodeEncodedPolyline(pts);
    if (pts is Map && pts['coordinates'] is List) {
      return _lineStringToLatLng(pts['coordinates'] as List);
    }
    throw StateError('NO_POINTS');
  }

  Future<List<LatLng>> _osrmFootRouteVia(List<LatLng> waypoints) async {
    final coord = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
    final url =
        '${OsrmConfig.footRouteBase}/$coord?overview=full&geometries=geojson';

    final response = await _dio.get<Map<String, dynamic>>(
      url,
      options: Options(
        receiveTimeout: const Duration(seconds: 60),
        headers: {'User-Agent': 'HikingApp/1.0 (OSRM foot fallback)'},
      ),
    );

    final data = response.data;
    if (data == null) throw StateError('OSRM_EMPTY');
    final code = data['code']?.toString();
    if (code != null && code != 'Ok') {
      throw StateError(data['message']?.toString() ?? code);
    }
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) throw StateError('OSRM_NO_ROUTES');
    final first = routes.first;
    if (first is! Map<String, dynamic>) throw StateError('OSRM_BAD');
    final geom = first['geometry'];
    if (geom is Map && geom['coordinates'] is List) {
      final pts = _lineStringToLatLng(geom['coordinates'] as List);
      if (pts.length >= 2) return pts;
    }
    throw StateError('OSRM_NO_GEOM');
  }

  Future<List<LatLng>> _chainLegRoutes(List<LatLng> waypoints) async {
    final out = <LatLng>[];
    final key = GraphHopperConfig.apiKey.trim();
    for (var i = 0; i < waypoints.length - 1; i++) {
      final a = waypoints[i];
      final b = waypoints[i + 1];
      List<LatLng> seg = [a, b];
      var gotTrail = false;
      if (key.isNotEmpty) {
        try {
          final g = await _graphHopperRouteVia([a, b]);
          if (g.length >= 2) {
            seg = g;
            gotTrail = true;
          }
        } catch (_) {}
      }
      if (!gotTrail) {
        try {
          final o = await _osrmFootRouteVia([a, b]);
          if (o.length >= 2) {
            seg = o;
            gotTrail = true;
          }
        } catch (_) {}
      }
      _appendSegmentPolyline(out, seg);
    }
    return out;
  }
}

void _appendSegmentPolyline(List<LatLng> out, List<LatLng> seg) {
  const dist = Distance();
  if (seg.isEmpty) return;
  if (out.isEmpty) {
    out.addAll(seg);
    return;
  }
  final gap = dist.as(LengthUnit.Meter, out.last, seg.first);
  if (gap < 5) {
    out.addAll(seg.skip(1));
  } else {
    out.addAll(seg);
  }
}

List<LatLng> _lineStringToLatLng(List coords) {
  final out = <LatLng>[];
  for (final c in coords) {
    if (c is List && c.length >= 2) {
      out.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
    }
  }
  return out;
}

List<LatLng> _decodeEncodedPolyline(String encoded) {
  final poly = <LatLng>[];
  var index = 0;
  final len = encoded.length;
  var lat = 0;
  var lng = 0;
  while (index < len) {
    var result = 0;
    var shift = 0;
    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += dlat;
    result = 0;
    shift = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += dlng;
    poly.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return poly;
}
