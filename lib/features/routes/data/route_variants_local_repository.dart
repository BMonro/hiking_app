import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/routing_config.dart';
import '../domain/hike_duration_estimate.dart';
import '../domain/route_variant.dart';

class _ParsedPath {
  _ParsedPath({
    required this.points,
    required this.distanceM,
    required this.timeMs,
    required this.ascentM,
  });

  final List<LatLng> points;
  final double distanceM;
  final int timeMs;
  final int ascentM;
}

class RouteVariantsLocalRepository {
  RouteVariantsLocalRepository({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const _distance = Distance();

  Future<List<RouteVariant>> fetchVariants(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return [];

    final key = GraphHopperConfig.apiKey.trim();
    var paths = <_ParsedPath>[];

    if (key.isNotEmpty) {
      paths = await _collectGraphHopper(waypoints, key);
    }
    if (paths.length < 3) {
      paths = _dedupe([...paths, ...await _collectOsrm(waypoints, paths)]);
    }

    if (paths.isEmpty) return [];
    return _labelVariants(paths.take(3).toList());
  }

  Future<List<_ParsedPath>> _collectGraphHopper(
    List<LatLng> waypoints,
    String key,
  ) async {
    final collected = <_ParsedPath>[];

    try {
      collected.addAll(
        await _requestGh(
          waypoints,
          key,
          '&algorithm=alternative_route&alternative_route.max_paths=3'
              '&alternative_route.max_weight_factor=2.2'
              '&alternative_route.max_share_factor=0.8'
              '&ch.disable=true',
        ),
      );
    } catch (_) {}

    try {
      final direct = (await _requestGh(waypoints, key, '')).firstOrNull;
      if (direct != null && !_poolHasSimilar(collected, direct)) {
        collected.add(direct);
      }
    } catch (_) {}

    var deduped = _dedupe(collected);

    if (deduped.length < 3 && waypoints.length == 2) {
      final extra = await _discoverVia(
        waypoints.first,
        waypoints.last,
        deduped,
        (wps) => _requestGh(wps, key, '').then((l) => l.first),
      );
      deduped = _dedupe([...deduped, ...extra]);
    }
    return deduped;
  }

  Future<List<_ParsedPath>> _collectOsrm(
    List<LatLng> waypoints,
    List<_ParsedPath> existing,
  ) async {
    final collected = [...existing];

    try {
      for (final p in await _requestOsrm(waypoints, alternatives: true)) {
        if (!_poolHasSimilar(collected, p)) collected.add(p);
      }
    } catch (_) {}

    if (collected.length < 3 && waypoints.length == 2) {
      final extra = await _discoverVia(
        waypoints.first,
        waypoints.last,
        collected,
        (wps) async {
          final list = await _requestOsrm(wps);
          return list.isEmpty ? null : list.first;
        },
      );
      for (final p in extra) {
        if (!_poolHasSimilar(collected, p)) collected.add(p);
      }
    }

    return _dedupe(collected);
  }

  Future<List<_ParsedPath>> _discoverVia(
    LatLng a,
    LatLng b,
    List<_ParsedPath> existing,
    Future<_ParsedPath?> Function(List<LatLng>) fetch,
  ) async {
    final found = <_ParsedPath>[];
    final results = await Future.wait(
      _viaCandidates(a, b).map((via) => fetch([a, via, b])),
    );
    for (final path in results) {
      if (path == null) continue;
      if (existing.length + found.length >= 3) break;
      if (!_poolHasSimilar([...existing, ...found], path)) found.add(path);
    }
    return found;
  }

  List<LatLng> _viaCandidates(LatLng a, LatLng b) {
    final distM = _distance.as(LengthUnit.Meter, a, b);
    final scale = (distM / 6000).clamp(1.0, 2.5);
    final offsets = [0.8, 2.0, 4.0, 7.0, -0.8, -2.0, -4.0, -7.0]
        .map((k) => k * scale)
        .toList();
    final dLat = b.latitude - a.latitude;
    final dLon = b.longitude - a.longitude;
    final len = math.sqrt(dLat * dLat + dLon * dLon);
    if (len < 1e-9) return [];
    final pLat = -dLon / len;
    final pLon = dLat / len;

    final out = <LatLng>[];
    for (final frac in [0.3, 0.5, 0.7]) {
      final midLat = a.latitude + dLat * frac;
      final midLon = a.longitude + dLon * frac;
      final lonScale = 111320 * math.cos(midLat * math.pi / 180);
      for (final km in offsets) {
        out.add(
          LatLng(
            midLat + pLat * km * 1000 / 111320,
            midLon + pLon * km * 1000 / lonScale,
          ),
        );
      }
    }
    return out;
  }

  Future<List<_ParsedPath>> _requestGh(
    List<LatLng> waypoints,
    String key,
    String extra,
  ) async {
    final query = StringBuffer();
    for (var i = 0; i < waypoints.length; i++) {
      final p = waypoints[i];
      if (i > 0) query.write('&');
      query.write('point=${p.latitude},${p.longitude}');
    }
    query.write(
      '&vehicle=hike&locale=uk&points_encoded=true&key='
      '${Uri.encodeQueryComponent(key)}$extra',
    );

    final response = await _dio.get<Map<String, dynamic>>(
      '${GraphHopperConfig.routeUrl}?${query.toString()}',
      options: Options(
        receiveTimeout: const Duration(seconds: 90),
        headers: {'User-Agent': 'Hikora/1.0 (local variants)'},
      ),
    );

    final data = response.data;
    if (data == null) throw StateError('EMPTY');
    final message = data['message']?.toString();
    if (message != null && message.isNotEmpty) throw StateError(message);

    final paths = data['paths'];
    if (paths is! List || paths.isEmpty) throw StateError('NO_PATH');

    final out = <_ParsedPath>[];
    for (final raw in paths) {
      if (raw is! Map<String, dynamic>) continue;
      final parsed = _parseGhPath(raw);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  _ParsedPath? _parseGhPath(Map<String, dynamic> path) {
    final pts = path['points'];
    List<LatLng> points = [];
    if (pts is String && pts.isNotEmpty) {
      points = _decodePolyline(pts);
    } else if (pts is Map && pts['coordinates'] is List) {
      points = _lineStringToLatLng(pts['coordinates'] as List);
    }
    if (points.length < 2) return null;

    return _ParsedPath(
      points: points,
      distanceM: (path['distance'] as num?)?.toDouble() ?? 0,
      timeMs: (path['time'] as num?)?.round() ?? 0,
      ascentM: ((path['ascend'] ?? path['ascent']) as num?)?.round() ?? 0,
    );
  }

  Future<List<_ParsedPath>> _requestOsrm(
    List<LatLng> waypoints, {
    bool alternatives = false,
  }) async {
    final coord =
        waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
    var url =
        '${OsrmConfig.footRouteBase}/$coord?overview=full&geometries=geojson&steps=false';
    if (alternatives && waypoints.length == 2) url += '&alternatives=3';

    final response = await _dio.get<Map<String, dynamic>>(
      url,
      options: Options(
        receiveTimeout: const Duration(seconds: 60),
        headers: {'User-Agent': 'Hikora/1.0 (OSRM variants)'},
      ),
    );

    final data = response.data;
    if (data == null) throw StateError('OSRM_EMPTY');
    final code = data['code']?.toString();
    if (code != null && code != 'Ok') {
      throw StateError(data['message']?.toString() ?? code);
    }

    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) throw StateError('NO_ROUTES');

    final out = <_ParsedPath>[];
    for (final raw in routes) {
      if (raw is! Map<String, dynamic>) continue;
      final geom = raw['geometry'];
      if (geom is! Map || geom['coordinates'] is! List) continue;
      final points = _lineStringToLatLng(geom['coordinates'] as List);
      if (points.length < 2) continue;
      final durationSec = (raw['duration'] as num?)?.toDouble() ?? 0;
      out.add(
        _ParsedPath(
          points: points,
          distanceM: (raw['distance'] as num?)?.toDouble() ?? 0,
          timeMs: (durationSec * 1000).round(),
          ascentM: 0,
        ),
      );
    }
    return out;
  }

  bool _poolHasSimilar(List<_ParsedPath> pool, _ParsedPath p) =>
      pool.any((o) => _areSimilar(o, p));

  bool _areSimilar(_ParsedPath a, _ParsedPath b) {
    final lenRatio = (a.distanceM - b.distanceM).abs() /
        math.max(math.max(a.distanceM, b.distanceM), 1);
    if (lenRatio > 0.12) return false;

    final midA = a.points[a.points.length ~/ 2];
    final midB = b.points[b.points.length ~/ 2];
    if (_distance.as(LengthUnit.Meter, midA, midB) > 500) return false;

    const samples = 5;
    var sum = 0.0;
    for (var i = 0; i < samples; i++) {
      final idx = ((a.points.length - 1) * i / math.max(samples - 1, 1))
          .round();
      sum += _minDistToPoly(a.points[idx], b.points);
    }
    return sum / samples < 250;
  }

  double _minDistToPoly(LatLng p, List<LatLng> poly) {
    var min = double.infinity;
    for (final q in poly) {
      final d = _distance.as(LengthUnit.Meter, p, q);
      if (d < min) min = d;
    }
    return min;
  }

  List<_ParsedPath> _dedupe(List<_ParsedPath> paths) {
    final out = <_ParsedPath>[];
    for (final p in paths) {
      if (!out.any((o) => _areSimilar(o, p))) out.add(p);
    }
    return out;
  }

  List<RouteVariant> _labelVariants(List<_ParsedPath> paths) {
    final items = paths
        .map(
          (p) => (
            stats: _statsFrom(p),
            points: p.points,
          ),
        )
        .toList();
    items.sort((a, b) => _effort(a.stats).compareTo(_effort(b.stats)));

    final labels = _difficultyLabels(items.length, items);
    return List.generate(items.length, (i) {
      final d = labels[i];
      final s = items[i].stats;
      return RouteVariant(
        difficulty: d,
        difficultyLabel: _difficultyLabelUk(d),
        distanceKm: s.distanceKm,
        durationH: s.durationH,
        ascentM: s.ascentM,
        points: items[i].points,
      );
    });
  }

  ({double distanceKm, double durationH, int ascentM}) _statsFrom(
    _ParsedPath p,
  ) {
    const dist = Distance();
    final segments = <HikeSegmentInput>[];
    for (var i = 1; i < p.points.length; i++) {
      segments.add(
        HikeSegmentInput(
          distanceM: dist.as(
            LengthUnit.Meter,
            p.points[i - 1],
            p.points[i],
          ),
        ),
      );
    }
    var estimate = HikeDurationEstimate.fromSegments(segments);
    if (p.ascentM > estimate.ascentM) {
      final extra = p.ascentM - estimate.ascentM;
      final extraH = (extra / 100.0) * (10 / 60) * 1.08;
      estimate = HikeDurationResult(
        distanceKm: estimate.distanceKm,
        ascentM: p.ascentM,
        descentM: estimate.descentM,
        durationH: double.parse(
          (estimate.durationH + extraH).toStringAsFixed(1),
        ),
      );
    }
    var durationH = estimate.durationH;
    if (p.timeMs > 0) {
      final ghH = p.timeMs / 3600000;
      durationH = double.parse(
        math.max(durationH, ghH).toStringAsFixed(1),
      );
    }
    return (
      distanceKm: estimate.distanceKm,
      durationH: durationH,
      ascentM: p.ascentM,
    );
  }

  double _effort(({double distanceKm, double durationH, int ascentM}) s) =>
      s.ascentM * 2 + s.distanceKm * 10 + s.durationH * 5;

  List<String> _difficultyLabels(
    int n,
    List<({({double distanceKm, double durationH, int ascentM}) stats, List<LatLng> points})> sorted,
  ) {
    if (n == 1) {
      return [_classifyAbsolute(sorted.first.stats)];
    }
    if (n == 2) {
      final ratio = _effort(sorted[1].stats) /
          math.max(_effort(sorted[0].stats), 1);
      return ratio < 1.12 ? ['easy', 'medium'] : ['easy', 'hard'];
    }
    return ['easy', 'medium', 'hard'];
  }

  String _classifyAbsolute(({double distanceKm, double durationH, int ascentM}) s) {
    final e = _effort(s);
    if (e < 90) return 'easy';
    if (e > 170) return 'hard';
    return 'medium';
  }

  String _difficultyLabelUk(String d) => switch (d) {
        'easy' => 'Легкий',
        'hard' => 'Важкий',
        _ => 'Середній',
      };

  List<LatLng> _lineStringToLatLng(List coords) {
    final out = <LatLng>[];
    for (final c in coords) {
      if (c is List && c.length >= 2) {
        out.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
      }
    }
    return out;
  }

  List<LatLng> _decodePolyline(String encoded) {
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
}
