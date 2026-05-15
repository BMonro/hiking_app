import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../../routes/domain/route_detail.dart';
import '../../routes/domain/route_model.dart';

class OfflineMapDownloadProgress {
  final int completed;
  final int total;

  const OfflineMapDownloadProgress({
    required this.completed,
    required this.total,
  });

  double get fraction => total == 0 ? 0 : completed / total;
}

class OfflineMapService {
  static const String osmTileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const int minZoom = 11;
  static const int maxZoom = 16;
  static const double boundsPaddingDegrees = 0.02;

  final Dio _dio;

  OfflineMapService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                headers: const {
                  'User-Agent': 'HikingApp/1.0 (com.example.hiking_app)',
                },
              ),
            );

  Future<Directory> _routeDir(String routeId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/offline_tiles/$routeId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _metadataFile(String routeId) async {
    final dir = await _routeDir(routeId);
    return File('${dir.path}/route_detail.json');
  }

  Future<File> _completeMarker(String routeId) async {
    final dir = await _routeDir(routeId);
    return File('${dir.path}/.complete');
  }

  String tileFilePath(String routeId, int z, int x, int y) {
    return '${_offlineRootSync()}/$routeId/$z/$x/$y.png';
  }

  String _offlineRootSync() {
    // Used only from sync tile provider after the first async lookup.
    return _cachedOfflineRoot ?? '';
  }

  String? _cachedOfflineRoot;

  Future<void> ensureOfflineRootCached() async {
    _cachedOfflineRoot ??=
        '${(await getApplicationDocumentsDirectory()).path}/offline_tiles';
  }

  Future<bool> hasOfflineMap(String routeId) async {
    if ((await _completeMarker(routeId)).existsSync()) return true;
    return (await _metadataFile(routeId)).existsSync();
  }

  Future<List<RouteDetail>> listDownloadedRoutes() async {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory('${base.path}/offline_tiles');
    if (!await root.exists()) return [];

    final routesById = <String, RouteDetail>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('route_detail.json')) continue;

      try {
        final json = jsonDecode(await entity.readAsString());
        if (json is! Map) continue;
        final detail = _decodeRouteDetail(Map<String, dynamic>.from(json));
        routesById[detail.route.id] = detail;
      } catch (_) {
        final routeId = _routeIdFromPath(entity.parent.path);
        if (routeId.isEmpty) continue;
        routesById.putIfAbsent(
          routeId,
          () => RouteDetail(
            route: RouteModel(
              id: routeId,
              title: 'Завантажений маршрут',
              routeType: 'linear',
              difficulty: 'easy',
              distanceKm: 0,
              ascentM: 0,
              durationH: 0,
              description: '',
              authorId: '',
              createdAt: DateTime.now(),
            ),
            waypoints: const [],
          ),
        );
      }
    }

    final routes = routesById.values.toList();
    routes.sort(
      (a, b) => a.route.title.toLowerCase().compareTo(
            b.route.title.toLowerCase(),
          ),
    );
    return routes;
  }

  Future<RouteDetail?> loadCachedRouteDetail(String routeId) async {
    final file = await _metadataFile(routeId);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      return _decodeRouteDetail(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  String _routeIdFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/').where((part) => part.isNotEmpty);
    if (segments.isEmpty) return '';
    return segments.last;
  }

  Future<double> cacheSizeMb(String routeId) async {
    final dir = await _routeDir(routeId);
    if (!await dir.exists()) return 0;
    var bytes = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        bytes += await entity.length();
      }
    }
    return bytes / (1024 * 1024);
  }

  Stream<OfflineMapDownloadProgress> downloadRouteMap(RouteDetail detail) async* {
    final routeId = detail.route.id;
    final points = _collectCoveragePoints(detail);
    if (points.isEmpty) {
      throw StateError('Немає координат для завантаження карти');
    }

    final bounds = _boundsForPoints(points);
    final tiles = <({int z, int x, int y})>[];
    for (var z = minZoom; z <= maxZoom; z++) {
      tiles.addAll(_tilesForBounds(bounds, z));
    }

    final dir = await _routeDir(routeId);
    final marker = await _completeMarker(routeId);
    if (await marker.exists()) {
      await marker.delete();
    }

    var completed = 0;
    yield OfflineMapDownloadProgress(completed: completed, total: tiles.length);

    const batchSize = 6;
    for (var i = 0; i < tiles.length; i += batchSize) {
      final batch = tiles.skip(i).take(batchSize).toList();
      await Future.wait(
        batch.map((tile) async {
          final file = File('${dir.path}/${tile.z}/${tile.x}/${tile.y}.png');
          if (await file.exists()) {
            completed++;
            return;
          }
          await file.parent.create(recursive: true);
          final url = osmTileUrlTemplate
              .replaceAll('{z}', '${tile.z}')
              .replaceAll('{x}', '${tile.x}')
              .replaceAll('{y}', '${tile.y}');
          try {
            final response = await _dio.get<List<int>>(
              url,
              options: Options(responseType: ResponseType.bytes),
            );
            final bytes = response.data;
            if (bytes != null && bytes.isNotEmpty) {
              await file.writeAsBytes(bytes, flush: true);
            }
          } on DioException {
            // Skip failed tiles; cached tiles remain usable offline.
          }
          completed++;
        }),
      );
      yield OfflineMapDownloadProgress(
        completed: completed,
        total: tiles.length,
      );
    }

    final metadata = await _metadataFile(routeId);
    await metadata.writeAsString(
      jsonEncode(_encodeRouteDetail(detail)),
      flush: true,
    );
    await marker.writeAsString('1', flush: true);
    await ensureOfflineRootCached();
  }

  Future<void> deleteOfflineMap(String routeId) async {
    final dir = await _routeDir(routeId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  List<LatLng> _collectCoveragePoints(RouteDetail detail) {
    final points = <LatLng>[];
    if (detail.polyline != null) {
      points.addAll(detail.polyline!);
    }
    points.addAll(detail.waypoints.map((w) => w.position));
    return points;
  }

  ({double minLat, double maxLat, double minLon, double maxLon}) _boundsForPoints(
    List<LatLng> points,
  ) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLon = points.first.longitude;
    var maxLon = points.first.longitude;
    for (final p in points.skip(1)) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }
    return (
      minLat: minLat - boundsPaddingDegrees,
      maxLat: maxLat + boundsPaddingDegrees,
      minLon: minLon - boundsPaddingDegrees,
      maxLon: maxLon + boundsPaddingDegrees,
    );
  }

  List<({int z, int x, int y})> _tilesForBounds(
    ({double minLat, double maxLat, double minLon, double maxLon}) bounds,
    int zoom,
  ) {
    final minX = _lonToTileX(bounds.minLon, zoom);
    final maxX = _lonToTileX(bounds.maxLon, zoom);
    final minY = _latToTileY(bounds.maxLat, zoom);
    final maxY = _latToTileY(bounds.minLat, zoom);
    final tiles = <({int z, int x, int y})>[];
    for (var x = minX; x <= maxX; x++) {
      for (var y = minY; y <= maxY; y++) {
        tiles.add((z: zoom, x: x, y: y));
      }
    }
    return tiles;
  }

  int _lonToTileX(double lon, int zoom) {
    return ((lon + 180) / 360 * math.pow(2, zoom)).floor();
  }

  int _latToTileY(double lat, int zoom) {
    final latRad = lat * math.pi / 180;
    return ((1 -
                math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
                    2 *
                math.pow(2, zoom))
            .floor();
  }

  Map<String, dynamic> _encodeRouteDetail(RouteDetail detail) {
    return {
      'route': {
        'id': detail.route.id,
        'title': detail.route.title,
        'route_type': detail.route.routeType,
        'difficulty': detail.route.difficulty,
        'distance_km': detail.route.distanceKm,
        'ascent_m': detail.route.ascentM,
        'duration_h': detail.route.durationH,
        'description': detail.route.description,
        'cover_image_url': detail.route.coverImageUrl,
        'author_id': detail.route.authorId,
        'created_at': detail.route.createdAt.toIso8601String(),
      },
      'waypoints': detail.waypoints
          .map(
            (w) => {
              'name': w.name,
              'latitude': w.position.latitude,
              'longitude': w.position.longitude,
              'point_type': w.pointType,
              'sort_order': w.sortOrder,
              'altitude_m': w.altitudeM,
            },
          )
          .toList(),
      'polyline': detail.polyline
          ?.map((p) => [p.latitude, p.longitude])
          .toList(),
    };
  }

  RouteDetail _decodeRouteDetail(Map<String, dynamic> json) {
    final routeJson = Map<String, dynamic>.from(json['route'] as Map);
    final createdAtRaw = routeJson['created_at'];
    if (createdAtRaw == null) {
      routeJson['created_at'] = DateTime.now().toIso8601String();
    } else if (createdAtRaw is! String) {
      routeJson['created_at'] = createdAtRaw.toString();
    }
    final route = RouteModel.fromJson(routeJson);
    final waypoints = <RouteWaypoint>[];
    final rawWaypoints = json['waypoints'];
    if (rawWaypoints is List) {
      for (final item in rawWaypoints) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final lat = (m['latitude'] as num?)?.toDouble();
        final lon = (m['longitude'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        waypoints.add(
          RouteWaypoint(
            name: m['name']?.toString(),
            position: LatLng(lat, lon),
            pointType: m['point_type']?.toString() ?? 'start',
            sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
            altitudeM: (m['altitude_m'] as num?)?.toInt(),
          ),
        );
      }
    }

    List<LatLng>? polyline;
    final rawPolyline = json['polyline'];
    if (rawPolyline is List) {
      final pts = <LatLng>[];
      for (final item in rawPolyline) {
        if (item is List && item.length >= 2) {
          pts.add(
            LatLng(
              (item[0] as num).toDouble(),
              (item[1] as num).toDouble(),
            ),
          );
        }
      }
      if (pts.length >= 2) {
        polyline = pts;
      }
    }

    return RouteDetail(
      route: route,
      waypoints: waypoints,
      polyline: polyline,
    );
  }
}
