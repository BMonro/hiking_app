import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../core/api/backend_api.dart';
import '../../../core/config/overpass_config.dart';
import '../domain/map_poi.dart';

/// POI з Overpass через Edge Function `poi-nearby` (локальний fallback).
class OverpassPoiRepository {
  OverpassPoiRepository({Dio? dio, BackendApi? api})
      : _dio = dio ?? Dio(),
        _api = api ?? BackendApi();

  final Dio _dio;
  final BackendApi _api;

  Future<List<MapPoi>?> fetchPoisInBounds(
    LatLngBounds bounds, {
    String endpoint = OverpassConfig.interpreterUrl,
  }) async {
    final sw = bounds.southWest;
    final ne = bounds.northEast;

    try {
      final data = await _api.invoke(
        'poi-nearby',
        body: {
          'south': sw.latitude,
          'west': sw.longitude,
          'north': ne.latitude,
          'east': ne.longitude,
        },
        timeout: const Duration(seconds: 55),
      );
      if (data['zoom_too_low'] == true) return null;
      return _parsePois(data['pois']);
    } catch (_) {
      return _fetchPoisLocal(bounds, endpoint);
    }
  }

  List<MapPoi> _parsePois(dynamic raw) {
    if (raw is! List) return [];
    final list = <MapPoi>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final kindStr = m['kind']?.toString() ?? 'other';
      list.add(
        MapPoi(
          lat: (m['lat'] as num).toDouble(),
          lon: (m['lon'] as num).toDouble(),
          kind: _kindFromString(kindStr),
          name: m['name']?.toString(),
          elevationM: (m['elevation_m'] as num?)?.toInt(),
        ),
      );
    }
    return list;
  }

  MapPoiKind _kindFromString(String s) {
    return switch (s) {
      'peak' => MapPoiKind.peak,
      'water' => MapPoiKind.water,
      'shelter' => MapPoiKind.shelter,
      'hut' => MapPoiKind.hut,
      'viewpoint' => MapPoiKind.viewpoint,
      'picnicSite' => MapPoiKind.picnicSite,
      'campSite' => MapPoiKind.campSite,
      'attraction' => MapPoiKind.attraction,
      'historic' => MapPoiKind.historic,
      'information' => MapPoiKind.information,
      _ => MapPoiKind.other,
    };
  }

  Future<List<MapPoi>?> _fetchPoisLocal(
    LatLngBounds bounds,
    String endpoint,
  ) async {
    final sw = bounds.southWest;
    final ne = bounds.northEast;
    final south = sw.latitude;
    final west = sw.longitude;
    final north = ne.latitude;
    final east = ne.longitude;

    final latSpan = (north - south).abs();
    final lonSpan = (east - west).abs();
    if (latSpan > 0.65 || lonSpan > 1.0) return null;

    final query = '''
[out:json][timeout:55];
(
  node["tourism"="alpine_hut"]($south,$west,$north,$east);
  node["natural"="peak"]($south,$west,$north,$east);
  node["amenity"="shelter"]($south,$west,$north,$east);
  node["tourism"="viewpoint"]($south,$west,$north,$east);
);
out center;
''';

    final response = await _dio.post<Map<String, dynamic>>(
      endpoint,
      data: query,
      options: Options(
        contentType: Headers.textPlainContentType,
        receiveTimeout: const Duration(seconds: 45),
        headers: {
          'User-Agent': 'HikingApp/1.0 (Flutter; tourism POI preview)',
        },
      ),
    );

    final data = response.data;
    if (data == null) return [];
    final elements = data['elements'];
    if (elements is! List) return [];

    final list = <MapPoi>[];
    for (final raw in elements) {
      if (raw is! Map) continue;
      final e = raw.cast<String, dynamic>();
      double? lat;
      double? lon;
      final type = e['type']?.toString();
      if (type == 'node') {
        lat = (e['lat'] as num?)?.toDouble();
        lon = (e['lon'] as num?)?.toDouble();
      } else if (type == 'way' || type == 'relation') {
        final c = e['center'];
        if (c is Map) {
          lat = (c['lat'] as num?)?.toDouble();
          lon = (c['lon'] as num?)?.toDouble();
        }
      }
      if (lat == null || lon == null) continue;
      final tagsRaw = e['tags'];
      final tags = <String, String>{};
      if (tagsRaw is Map) {
        for (final entry in tagsRaw.entries) {
          tags[entry.key.toString()] = entry.value?.toString() ?? '';
        }
      }
      list.add(
        MapPoi(
          lat: lat,
          lon: lon,
          kind: MapPoi.kindFromTags(tags),
          name: tags['name']?.trim(),
          elevationM: MapPoi.elevationMFromTags(tags),
        ),
      );
    }
    return list;
  }
}
