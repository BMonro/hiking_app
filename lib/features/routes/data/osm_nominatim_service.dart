import 'package:dio/dio.dart';

/// Кирилиця (українські/східнослов'янські назви).
final RegExp _cyrillicLabel = RegExp(r'[\u0400-\u04FF\u0490-\u052F]');

bool _hasCyrillic(String text) => _cyrillicLabel.hasMatch(text);

/// Найкраща українська назва з OSM-тегів / namedetails Nominatim.
String? _pickUkrainianNameFromTags(Map<String, dynamic> tags) {
  const keys = [
    'name:uk',
    'official_name:uk',
    'alt_name:uk',
    'name',
    'official_name',
    'alt_name',
  ];
  String? cyrillicFallback;
  for (final key in keys) {
    final v = tags[key]?.toString().trim();
    if (v == null || v.isEmpty) continue;
    if (_hasCyrillic(v)) return v;
    cyrillicFallback ??= v;
  }
  return cyrillicFallback;
}

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

    final rawNamedetails = json['namedetails'];
    final rawExtratags = json['extratags'];
    final tagMaps = <Map<String, dynamic>>[];
    if (rawNamedetails is Map) {
      tagMaps.add(Map<String, dynamic>.from(rawNamedetails));
    }
    if (rawExtratags is Map) {
      tagMaps.add(Map<String, dynamic>.from(rawExtratags));
    }

    String primary = (json['name'] as String?)?.trim() ?? '';
    for (final tags in tagMaps) {
      final fromTags = _pickUkrainianNameFromTags(tags);
      if (fromTags != null && fromTags.isNotEmpty) {
        primary = fromTags;
        break;
      }
    }

    final rawAddr = json['address'];
    if (primary.isEmpty) {
      primary = displayName.split(',').first.trim();
    }
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
          if (primary.isEmpty || _hasCyrillic(v)) primary = v;
          break;
        }
      }
    }

    int? ele;
    if (rawExtratags is Map) {
      final raw = Map<String, dynamic>.from(rawExtratags)['ele'];
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

  factory OsmPlaceResult.fromPhotonFeature(Map<String, dynamic> feature) {
    final geom = feature['geometry'];
    final props = feature['properties'];
    if (geom is! Map || props is! Map) {
      return const OsmPlaceResult(
        displayName: '',
        primaryLabel: '',
        lat: 0,
        lon: 0,
      );
    }
    final gm = Map<String, dynamic>.from(geom);
    final pm = Map<String, dynamic>.from(props);
    final coords = gm['coordinates'];
    if (coords is! List || coords.length < 2) {
      return const OsmPlaceResult(
        displayName: '',
        primaryLabel: '',
        lat: 0,
        lon: 0,
      );
    }
    final lon = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();

    final osmKey = pm['osm_key']?.toString();
    final osmValue = pm['osm_value']?.toString();
    final isPeak = osmKey == 'natural' &&
        (osmValue == 'peak' || osmValue == 'volcano' || osmValue == 'ridge');

    String primary = _pickUkrainianNameFromTags(pm) ?? '';
    if (primary.isEmpty) {
      for (final key in ['city', 'town', 'village', 'hamlet', 'locality', 'state']) {
        final v = pm[key]?.toString().trim();
        if (v != null && v.isNotEmpty) {
          primary = v;
          break;
        }
      }
    }
    if (primary.isEmpty) primary = 'Місце';

    final parts = <String>[
      if (pm['city'] != null) pm['city'].toString(),
      if (pm['state'] != null) pm['state'].toString(),
      if (pm['country'] != null) pm['country'].toString(),
    ].where((s) => s.trim().isNotEmpty).toList();
    var display = parts.isEmpty ? primary : '$primary · ${parts.join(', ')}';
    if (_hasCyrillic(primary)) {
      display = display
          .replaceAll('Ukraine', 'Україна')
          .replaceAll('Ukraine,', 'Україна,');
    }

    return OsmPlaceResult(
      displayName: display,
      primaryLabel: primary,
      lat: lat,
      lon: lon,
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
    final name = _pickUkrainianNameFromTags(tm) ?? 'Вершина';
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

/// Параметри пошуку OSM (швидкий режим для погоди vs повний для маршрутів).
class OsmSearchOptions {
  const OsmSearchOptions({
    this.includePeaks = true,
    this.countryCodes,
    this.viewbox,
    this.restrictToViewbox = true,
    this.nominatimLimit = 12,
    this.peakLimit = 15,
    this.detailedAddress = true,
    this.includeElevationTags = true,
    this.overpassTimeoutSec = 25,
  });

  /// Міста/села для погоди: Photon + Nominatim (Україна, bbox лише для пріоритету).
  static const weatherPlaces = OsmSearchOptions(
    includePeaks: false,
    countryCodes: 'ua',
    viewbox: _ukraineViewbox,
    restrictToViewbox: false,
    nominatimLimit: 12,
    peakLimit: 0,
    detailedAddress: true,
    includeElevationTags: true,
    overpassTimeoutSec: 0,
  );

  /// Вершини для погоди: Overpass у межах України (окремий запит).
  static const weatherPeaks = OsmSearchOptions(
    includePeaks: true,
    countryCodes: 'ua',
    viewbox: _ukraineViewbox,
    restrictToViewbox: true,
    nominatimLimit: 0,
    peakLimit: 12,
    detailedAddress: false,
    includeElevationTags: true,
    overpassTimeoutSec: 8,
  );

  /// Точки маршруту: міста/села (Photon + Nominatim, Україна).
  static const routePointPlaces = OsmSearchOptions(
    includePeaks: false,
    countryCodes: 'ua',
    viewbox: _ukraineViewbox,
    restrictToViewbox: false,
    nominatimLimit: 12,
    peakLimit: 0,
    detailedAddress: true,
    includeElevationTags: true,
    overpassTimeoutSec: 0,
  );

  /// Точки маршруту: вершини (Overpass, Україна).
  static const routePointPeaks = OsmSearchOptions(
    includePeaks: true,
    countryCodes: 'ua',
    viewbox: _ukraineViewbox,
    restrictToViewbox: true,
    nominatimLimit: 0,
    peakLimit: 15,
    detailedAddress: false,
    includeElevationTags: true,
    overpassTimeoutSec: 10,
  );

  static const _ukraineViewbox = (44.0, 22.0, 52.5, 41.0); // south, west, north, east

  final bool includePeaks;
  final String? countryCodes;
  final (double south, double west, double north, double east)? viewbox;
  /// Якщо false — Nominatim/Photon шукають ширше (краще для рідкісних назв).
  final bool restrictToViewbox;
  final int nominatimLimit;
  final int peakLimit;
  final bool detailedAddress;
  final bool includeElevationTags;
  final int overpassTimeoutSec;
}

/// Пошук місць через OpenStreetMap Nominatim + вершини (Overpass).
///
/// Дотримуйтесь [політики Nominatim](https://operations.osmfoundation.org/policies/nominatim/).
class OsmNominatimService {
  OsmNominatimService({Dio? dio, Dio? weatherDio})
      : _dio = dio ?? Dio(_baseOptions),
        _weatherDio = weatherDio ?? Dio(_weatherBaseOptions);

  static final Map<String, List<OsmPlaceResult>> _cache = {};
  static const _cacheMaxEntries = 48;

  static const _userAgent =
      'hiking_app/1.0 (Flutter; OSM route points; +https://openstreetmap.org/copyright)';

  static final BaseOptions _baseOptions = BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
    headers: <String, dynamic>{
      'User-Agent': _userAgent,
      'Accept-Language': 'uk,en;q=0.9',
    },
  );

  static final BaseOptions _weatherBaseOptions = BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 10),
    headers: <String, dynamic>{
      'User-Agent': _userAgent,
      'Accept-Language': 'uk,en;q=0.9',
    },
  );

  final Dio _dio;
  final Dio _weatherDio;

  /// Повний оптимізований пошук для точок маршруту (місця + вершини).
  Future<List<OsmPlaceResult>> search(
    String query, {
    CancelToken? cancelToken,
  }) async {
    final q = query.trim();
    if (q.length < 3) return const [];

    final cacheKey = 'route_full|$q';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final places = await searchForRoutePlaces(q, cancelToken: cancelToken);
    final peaks = await searchForRoutePeaks(q, cancelToken: cancelToken);
    final merged = _mergePreferPeaks(peaks, places, maxItems: 18);
    _remember(cacheKey, merged);
    return merged;
  }

  /// Міста, села, POI (Photon + Nominatim паралельно).
  Future<List<OsmPlaceResult>> searchForWeatherPlaces(
    String query, {
    CancelToken? cancelToken,
  }) =>
      _searchPhotonNominatimPlaces(
        query,
        options: OsmSearchOptions.weatherPlaces,
        cacheKeyPrefix: 'weather_places',
        cancelToken: cancelToken,
      );

  /// Вершини з OSM (Overpass, Україна) — окремий запит.
  Future<List<OsmPlaceResult>> searchForWeatherPeaks(
    String query, {
    CancelToken? cancelToken,
  }) =>
      _searchOverpassPeaksOnly(
        query,
        options: OsmSearchOptions.weatherPeaks,
        cacheKeyPrefix: 'weather_peaks',
        cancelToken: cancelToken,
      );

  /// Точки маршруту: міста/села (Photon + Nominatim).
  Future<List<OsmPlaceResult>> searchForRoutePlaces(
    String query, {
    CancelToken? cancelToken,
  }) =>
      _searchPhotonNominatimPlaces(
        query,
        options: OsmSearchOptions.routePointPlaces,
        cacheKeyPrefix: 'route_places',
        cancelToken: cancelToken,
      );

  /// Точки маршруту: вершини (Overpass).
  Future<List<OsmPlaceResult>> searchForRoutePeaks(
    String query, {
    CancelToken? cancelToken,
  }) =>
      _searchOverpassPeaksOnly(
        query,
        options: OsmSearchOptions.routePointPeaks,
        cacheKeyPrefix: 'route_peaks',
        cancelToken: cancelToken,
      );

  /// Об'єднати каталог, місця та вершини для підказок у формі.
  List<OsmPlaceResult> mergeRouteSuggestions(
    List<OsmPlaceResult> catalog,
    List<OsmPlaceResult> places,
    List<OsmPlaceResult> peaks, {
    int maxItems = 18,
  }) {
    final base = _mergePlaces(catalog, places, maxItems: maxItems);
    return _mergePreferPeaks(peaks, base, maxItems: maxItems);
  }

  Future<List<OsmPlaceResult>> _searchPhotonNominatimPlaces(
    String query, {
    required OsmSearchOptions options,
    required String cacheKeyPrefix,
    CancelToken? cancelToken,
  }) async {
    final q = query.trim();
    if (q.length < 3) return const [];

    final cacheKey = '$cacheKeyPrefix|$q';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final results = await Future.wait([
      _photonSearch(q, options: options, cancelToken: cancelToken)
          .timeout(const Duration(seconds: 5), onTimeout: () => const [])
          .catchError((_) => <OsmPlaceResult>[]),
      _nominatimSearch(
        q,
        options: options,
        cancelToken: cancelToken,
        dio: _weatherDio,
      )
          .timeout(const Duration(seconds: 8), onTimeout: () => const [])
          .catchError((_) => <OsmPlaceResult>[]),
    ]);

    // Nominatim першим — у відповіді українські назви (Accept-Language: uk).
    var list = _mergePlaces(results[1], results[0], maxItems: 14);
    if (list.isEmpty) {
      list = await _nominatimSearch(
        q,
        options: const OsmSearchOptions(
          includePeaks: false,
          nominatimLimit: 12,
          detailedAddress: true,
          includeElevationTags: true,
        ),
        cancelToken: cancelToken,
        dio: _dio,
      ).catchError((_) => <OsmPlaceResult>[]);
    }
    list = _sortUkrainianFirst(list);
    _remember(cacheKey, list);
    return list;
  }

  Future<List<OsmPlaceResult>> _searchOverpassPeaksOnly(
    String query, {
    required OsmSearchOptions options,
    required String cacheKeyPrefix,
    CancelToken? cancelToken,
  }) async {
    final q = query.trim();
    if (q.length < 3) return const [];

    final cacheKey = '$cacheKeyPrefix|$q';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    try {
      final peaks = await _overpassPeaks(
        q,
        options: options,
        cancelToken: cancelToken,
      ).timeout(
        Duration(seconds: options.overpassTimeoutSec + 2),
        onTimeout: () => const [],
      );
      final sorted = _sortUkrainianFirst(peaks);
      _remember(cacheKey, sorted);
      return sorted;
    } catch (_) {
      return const [];
    }
  }

  /// Повний пошук для погоди (місця + вершини).
  Future<List<OsmPlaceResult>> searchForWeather(
    String query, {
    CancelToken? cancelToken,
  }) async {
    final q = query.trim();
    if (q.length < 3) return const [];

    final cacheKey = 'weather_full|$q';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final places = await searchForWeatherPlaces(q, cancelToken: cancelToken);
    final peaks = await searchForWeatherPeaks(q, cancelToken: cancelToken);
    final merged = _mergePreferPeaks(peaks, places, maxItems: 18);
    _remember(cacheKey, merged);
    return merged;
  }

  static OsmPlaceResult _preferUkrainianLabel(
    OsmPlaceResult keep,
    OsmPlaceResult other,
  ) {
    final keepUa = _hasCyrillic(keep.primaryLabel);
    final otherUa = _hasCyrillic(other.primaryLabel);
    if (keepUa && !otherUa) return keep;
    if (otherUa && !keepUa) return other;
    return keep;
  }

  static List<OsmPlaceResult> _sortUkrainianFirst(List<OsmPlaceResult> list) {
    final copy = List<OsmPlaceResult>.from(list);
    copy.sort((a, b) {
      final ua = (_hasCyrillic(b.primaryLabel) ? 1 : 0)
          .compareTo(_hasCyrillic(a.primaryLabel) ? 1 : 0);
      if (ua != 0) return ua;
      return a.primaryLabel.compareTo(b.primaryLabel);
    });
    return copy;
  }

  static List<OsmPlaceResult> _mergePlaces(
    List<OsmPlaceResult> a,
    List<OsmPlaceResult> b, {
    int maxItems = 14,
  }) {
    final merged = <String, OsmPlaceResult>{};
    for (final r in [...a, ...b]) {
      if (r.lat == 0 && r.lon == 0) continue;
      final k = _dedupeKey(r.lat, r.lon);
      final existing = merged[k];
      merged[k] = existing == null ? r : _preferUkrainianLabel(existing, r);
    }
    return _sortUkrainianFirst(merged.values.toList()).take(maxItems).toList();
  }

  Future<List<OsmPlaceResult>> _photonSearch(
    String q, {
    required OsmSearchOptions options,
    CancelToken? cancelToken,
  }) async {
    final params = <String, dynamic>{
      'q': q,
      'limit': options.nominatimLimit,
      // Без lang — для UA-запитів частіше кирилиця; uk у Photon не підтримується.
    };
    final vb = options.viewbox;
    if (vb != null) {
      params['bbox'] = '${vb.$2},${vb.$1},${vb.$4},${vb.$3}';
    }

    final response = await _weatherDio.get<Map<String, dynamic>>(
      'https://photon.komoot.io/api/',
      queryParameters: params,
      cancelToken: cancelToken,
    );

    final features = response.data?['features'];
    if (features is! List) return const [];

    final out = <OsmPlaceResult>[];
    for (final f in features) {
      if (f is! Map) continue;
      final r = OsmPlaceResult.fromPhotonFeature(Map<String, dynamic>.from(f));
      if (r.lat == 0 && r.lon == 0) continue;
      out.add(r);
    }
    return out;
  }

  static void _remember(String key, List<OsmPlaceResult> list) {
    if (list.isEmpty) return;
    if (_cache.length >= _cacheMaxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = list;
  }

  Future<List<OsmPlaceResult>> _nominatimSearch(
    String q, {
    required OsmSearchOptions options,
    CancelToken? cancelToken,
    Dio? dio,
  }) async {
    final client = dio ?? _dio;
    final params = <String, dynamic>{
      'q': q,
      'format': 'json',
      'limit': options.nominatimLimit,
      'addressdetails': options.detailedAddress ? 1 : 0,
      'extratags': options.includeElevationTags ? 1 : 0,
      'namedetails': options.detailedAddress ? 1 : 0,
    };
    final vb = options.viewbox;
    if (vb != null) {
      // Nominatim: left, top, right, bottom = west, north, east, south
      params['viewbox'] = '${vb.$2},${vb.$3},${vb.$4},${vb.$1}';
      if (options.restrictToViewbox) {
        params['bounded'] = 1;
      }
    }
    if (options.countryCodes != null && options.countryCodes!.isNotEmpty) {
      params['countrycodes'] = options.countryCodes;
    }

    final response = await client.get<List<dynamic>>(
      'https://nominatim.openstreetmap.org/search',
      queryParameters: params,
      cancelToken: cancelToken,
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

  Future<List<OsmPlaceResult>> _overpassPeaks(
    String query, {
    required OsmSearchOptions options,
    CancelToken? cancelToken,
  }) async {
    final safe = RegExp.escape(query.trim());
    if (safe.length < 3) return const [];

    final vb = options.viewbox;
    final bboxFilter = vb != null
        ? '(${vb.$1},${vb.$2},${vb.$3},${vb.$4})'
        : '';
    final timeout = options.overpassTimeoutSec;
    final limit = options.peakLimit;

    final body = '''
[out:json][timeout:$timeout];
(
  node["natural"="peak"]["name"~"$safe",i]$bboxFilter;
  way["natural"="peak"]["name"~"$safe",i]$bboxFilter;
);
out center tags $limit;
''';

    final response = await _dio.post<Map<String, dynamic>>(
      'https://overpass-api.de/api/interpreter',
      data: body,
      cancelToken: cancelToken,
      options: Options(
        contentType: Headers.textPlainContentType,
        receiveTimeout: Duration(seconds: timeout + 5),
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
    List<OsmPlaceResult> nominatim, {
    int maxItems = 15,
  }) {
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
        final ua = (_hasCyrillic(b.primaryLabel) ? 1 : 0)
            .compareTo(_hasCyrillic(a.primaryLabel) ? 1 : 0);
        if (ua != 0) return ua;
        return a.primaryLabel.compareTo(b.primaryLabel);
      });

    return list.take(maxItems).toList();
  }
}
