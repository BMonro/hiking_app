import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../core/config/overpass_config.dart';
import '../domain/map_poi.dart';

/// Завантаження POI з OpenStreetMap через публічний Overpass API.
/// Ключ не потрібен; дотримуйтесь обмежень навантаження (див. коментар у кінці файлу).
class OverpassPoiRepository {
  OverpassPoiRepository({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// `null` — область екрана завелика (треба наблизити карту).
  Future<List<MapPoi>?> fetchPoisInBounds(
    LatLngBounds bounds, {
    String endpoint = OverpassConfig.interpreterUrl,
  }) async {
    final sw = bounds.southWest;
    final ne = bounds.northEast;
    final south = sw.latitude;
    final west = sw.longitude;
    final north = ne.latitude;
    final east = ne.longitude;

    final latSpan = (north - south).abs();
    final lonSpan = (east - west).abs();
    if (latSpan > 0.22 || lonSpan > 0.35) {
      return null;
    }

    final query = '''
[out:json][timeout:55];
(
  node["tourism"="alpine_hut"]($south,$west,$north,$east);
  node["tourism"="wilderness_hut"]($south,$west,$north,$east);
  node["tourism"="attraction"]($south,$west,$north,$east);
  node["tourism"="museum"]($south,$west,$north,$east);
  node["tourism"="gallery"]($south,$west,$north,$east);
  node["tourism"="artwork"]($south,$west,$north,$east);
  node["tourism"="zoo"]($south,$west,$north,$east);
  node["tourism"="theme_park"]($south,$west,$north,$east);
  node["tourism"="viewpoint"]($south,$west,$north,$east);
  node["tourism"="information"]($south,$west,$north,$east);
  node["tourism"="picnic_site"]($south,$west,$north,$east);
  node["tourism"="camp_site"]($south,$west,$north,$east);
  node["tourism"="caravan_site"]($south,$west,$north,$east);
  node["amenity"="shelter"]($south,$west,$north,$east);
  node["amenity"="drinking_water"]($south,$west,$north,$east);
  node["amenity"="fountain"]($south,$west,$north,$east);
  node["natural"="peak"]($south,$west,$north,$east);
  node["natural"="spring"]($south,$west,$north,$east);
  node["natural"="hot_spring"]($south,$west,$north,$east);
  node["man_made"="water_well"]($south,$west,$north,$east);
  node["historic"="castle"]($south,$west,$north,$east);
  node["historic"="ruins"]($south,$west,$north,$east);
  node["historic"="archaeological_site"]($south,$west,$north,$east);
  node["historic"="monument"]($south,$west,$north,$east);
  node["historic"="memorial"]($south,$west,$north,$east);
  node["historic"="wayside_shrine"]($south,$west,$north,$east);
  node["historic"="battlefield"]($south,$west,$north,$east);
  node["historic"="fort"]($south,$west,$north,$east);
  node["historic"="city_gate"]($south,$west,$north,$east);
  node["historic"="manor"]($south,$west,$north,$east);
  way["tourism"="alpine_hut"]($south,$west,$north,$east);
  way["tourism"="wilderness_hut"]($south,$west,$north,$east);
  way["amenity"="shelter"]($south,$west,$north,$east);
  way["natural"="peak"]($south,$west,$north,$east);
  way["tourism"="museum"]($south,$west,$north,$east);
  way["tourism"="picnic_site"]($south,$west,$north,$east);
  way["tourism"="camp_site"]($south,$west,$north,$east);
  way["tourism"="caravan_site"]($south,$west,$north,$east);
  way["historic"="castle"]($south,$west,$north,$east);
  way["historic"="ruins"]($south,$west,$north,$east);
  way["historic"="archaeological_site"]($south,$west,$north,$east);
  way["historic"="monument"]($south,$west,$north,$east);
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

      final name = tags['name']?.trim();
      final kind = MapPoi.kindFromTags(tags);
      list.add(
        MapPoi(
          lat: lat,
          lon: lon,
          kind: kind,
          name: name,
          elevationM: MapPoi.elevationMFromTags(tags),
        ),
      );
    }
    return list;
  }
}
