import 'package:dio/dio.dart';

/// Результат пошуку [Nominatim](https://nominatim.org/release-docs/develop/api/Search/) або Overpass (вершини).
class OsmPlaceResult {
  final String displayName;
  final String primaryLabel;
  final double lat;
  final double lon;
  final int? elevationM;
  /// Знайдено як вершину (natural=peak у OSM або клас peak у Nominatim).
  final bool isPeak;

  const OsmPlaceResult({
    required this.displayName,
    required this.primaryLabel,
    required this.lat,
    required this.lon,
    this.elevationM,
    this.isPeak = false,
  });

  factory OsmPlaceResult.fromNominatimJson(Map<String, dynamic> json) {
    final lat = double.parse((json['lat'] ?? '0').toString());
    final lon = double.parse((json['lon'] ?? '0').toString());
    final displayName = (json['display_name'] as String?)?.trim() ?? '';

    final cls = json['class']?.toString();
    final typ = json['type']?.toString();
    final isPeak = cls == 'natural' &&
        (typ == 'peak' ||
            typ == 'volcano' ||
            typ == 'ridge' ||
            typ == 'saddle');

    final rawAddr = json['address'];
    String primary = displayName.split(',').first.trim();
    if (rawAddr is Map) {
      final m = Map<String, dynamic>.from(rawAddr);
      for (final key in [
        'name',
        'peak',
        'summit',
        'mountain_pass',
        'village',
        'town',
        'city',
        'hamlet',
        'locality',
      ]) {
        final v = m[key]?.toString().trim();
        if (v != null && v.isNotEmpty) {
          primary = v;
          break;
        }
      }
    }

    int? ele;
    final rawTags = json['extratags'];
    if (rawTags is Map) {
      final raw = Map<String, dynamic>.from(rawTags)['ele'];
      if (raw != null) {
        ele = int.tryParse(raw.toString().replaceAll(RegExp(r'[^\d-]'), ''));
      }
    }

    return OsmPlaceResult(
      displayName: displayName.isEmpty ? primary : displayName,
      primaryLabel: primary,
      lat: lat,
      lon: lon,
      elevationM: ele,
      isPeak: isPeak,
    );
  }

  factory OsmPlaceResult.fromOverpassElement(Map<String, dynamic> el) {
    double? lat;
    double? lon;
    final type = el['type']?.toString();
    if (type == 'node') {
      lat = (el['lat'] as num?)?.toDouble();
      lon = (el['lon'] as num?)?.toDouble();
    } else {
      final c = el['center'];
      if (c is Map) {
        final cm = Map<String, dynamic>.from(c);
        lat = (cm['lat'] as num?)?.toDouble();
        lon = (cm['lon'] as num?)?.toDouble();
      }
    }

    final tags = el['tags'];
    final tm = tags is Map ? Map<String, dynamic>.from(tags) : <String, dynamic>{};
    final name = tm['name']?.toString().trim() ?? 'Вершина';
    final eleRaw = tm['ele'];
    final ele = eleRaw != null
        ? int.tryParse(eleRaw.toString().replaceAll(RegExp(r'[^\d-]'), ''))
        : null;

    final region = tm['nat_name'] ??
        tm['addr:region'] ??
        tm['is_in'] ??
        tm['addr:country'];
    final buf = StringBuffer(name);
    if (ele != null) buf.write(' · $ele м');
    if (region != null && region.toString().isNotEmpty) {
      buf.write(' — $region');
    }

    return OsmPlaceResult(
      displayName: buf.toString(),
      primaryLabel: name,
      lat: lat ?? 0,
      lon: lon ?? 0,
      elevationM: ele,
      isPeak: true,
    );
  }
}

/// Пошук місць через OpenStreetMap Nominatim + вершини (Overpass).
///
/// Дотримуйтесь [політики Nominatim](https://operations.osmfoundation.org/policies/nominatim/).
class OsmNominatimService {
  OsmNominatimService({Dio? dio}) : _dio = dio ?? Dio(_baseOptions);

  static final BaseOptions _baseOptions = BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: <String, dynamic>{
      'User-Agent':
          'hiking_app/1.0 (Flutter; OSM route points; +https://openstreetmap.org/copyright)',
      'Accept-Language': 'uk,en;q=0.9',
    },
  );

  final Dio _dio;

  /// Шукати звичайні об'єкти (Nominatim) і доповнювати вершинами з Overpass.
  /// Nominatim і Overpass виконуються паралельно — сумарний час ≈ max, а не сума.
  Future<List<OsmPlaceResult>> search(String query) async {
    final q = query.trim();
    if (q.length < 3) return const [];

    final results = await Future.wait([
      _nominatimSearch(q).catchError((_) => <OsmPlaceResult>[]),
      _overpassPeaks(q).catchError((_) => <OsmPlaceResult>[]),
    ]);

    return _mergePreferPeaks(results[1], results[0]);
  }

  Future<List<OsmPlaceResult>> _nominatimSearch(String q) async {
    final response = await _dio.get<List<dynamic>>(
      'https://nominatim.openstreetmap.org/search',
      queryParameters: <String, dynamic>{
        'q': q,
        'format': 'json',
        'limit': 12,
        'addressdetails': 1,
        'extratags': 1,
      },
    );

    final data = response.data;
    if (data == null) return const [];

    return data
        .map(
          (e) =>
              OsmPlaceResult.fromNominatimJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<List<OsmPlaceResult>> _overpassPeaks(String query) async {
    final safe = RegExp.escape(query.trim());
    if (safe.length < 3) return const [];

    final body = '''
[out:json][timeout:25];
(
  node["natural"="peak"]["name"~"$safe",i];
  way["natural"="peak"]["name"~"$safe",i];
);
out center tags 15;
''';

    final response = await _dio.post<Map<String, dynamic>>(
      'https://overpass-api.de/api/interpreter',
      data: body,
      options: Options(
        contentType: Headers.textPlainContentType,
        headers: <String, dynamic>{
          'User-Agent': _baseOptions.headers['User-Agent']!,
        },
      ),
    );

    final data = response.data;
    if (data == null) return const [];

    final elements = data['elements'];
    if (elements is! List) return const [];

    final out = <OsmPlaceResult>[];
    for (final e in elements) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final r = OsmPlaceResult.fromOverpassElement(m);
      if (r.lat == 0 && r.lon == 0) continue;
      out.add(r);
    }
    return out;
  }

  static String _dedupeKey(double lat, double lon) =>
      '${(lat * 10000).round()}_${(lon * 10000).round()}';

  List<OsmPlaceResult> _mergePreferPeaks(
    List<OsmPlaceResult> peaks,
    List<OsmPlaceResult> nominatim,
  ) {
    final merged = <String, OsmPlaceResult>{};

    for (final p in peaks) {
      merged[_dedupeKey(p.lat, p.lon)] = p;
    }
    for (final n in nominatim) {
      final k = _dedupeKey(n.lat, n.lon);
      merged.putIfAbsent(k, () => n);
    }

    final list = merged.values.toList()
      ..sort((a, b) {
        final pk = (b.isPeak ? 1 : 0).compareTo(a.isPeak ? 1 : 0);
        if (pk != 0) return pk;
        return a.primaryLabel.compareTo(b.primaryLabel);
      });

    return list.take(15).toList();
  }
}
