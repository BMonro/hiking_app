import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../../routes/domain/route_detail.dart';
import '../domain/offline_map_package.dart';

class OfflineMapDownloadProgress {
  final int completed;
  final int total;

  const OfflineMapDownloadProgress({
    required this.completed,
    required this.total,
  });

  double get fraction => total == 0 ? 0 : completed / total;
}

/// Завантаження та зберігання **тільки картографічних тайлів** OSM.
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

  String? _cachedOfflineRoot;

  Future<Directory> _routeDir(String routeId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/offline_tiles/$routeId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _metaFile(String routeId) async {
    final dir = await _routeDir(routeId);
    return File('${dir.path}/map_meta.json');
  }

  Future<File> _completeMarker(String routeId) async {
    final dir = await _routeDir(routeId);
    return File('${dir.path}/.complete');
  }

  Future<File> _legacyDetailFile(String routeId) async {
    final dir = await _routeDir(routeId);
    return File('${dir.path}/route_detail.json');
  }

  String tileFilePath(String routeId, int z, int x, int y) {
    return '${_offlineRootSync()}/$routeId/$z/$x/$y.png';
  }

  String _offlineRootSync() => _cachedOfflineRoot ?? '';

  Future<void> ensureOfflineRootCached() async {
    _cachedOfflineRoot ??=
        '${(await getApplicationDocumentsDirectory()).path}/offline_tiles';
  }

  /// Карта завантажена повністю (є маркер завершення).
  Future<bool> hasOfflineMap(String routeId) async {
    return (await _completeMarker(routeId)).existsSync();
  }

  Future<List<OfflineMapPackage>> listOfflineMaps() async {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory('${base.path}/offline_tiles');
    if (!await root.exists()) return [];

    final packages = <OfflineMapPackage>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final routeId = entity.path.split(Platform.pathSeparator).last;
      if (routeId.isEmpty || routeId.startsWith('.')) continue;

      await _migrateLegacyDetailIfNeeded(routeId);
      final meta = await _readMeta(routeId);
      if (meta == null) continue;
      if (!await hasOfflineMap(routeId)) continue;

      final tileCount = await _countTiles(routeId);
      packages.add(
        OfflineMapPackage(
          routeId: meta.routeId,
          title: meta.title,
          downloadedAt: meta.downloadedAt,
          tileCount: tileCount,
        ),
      );
    }

    packages.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return packages;
  }

  Future<OfflineMapPackage?> getOfflineMap(String routeId) async {
    if (!await hasOfflineMap(routeId)) return null;
    await _migrateLegacyDetailIfNeeded(routeId);
    final meta = await _readMeta(routeId);
    if (meta == null) return null;
    return OfflineMapPackage(
      routeId: meta.routeId,
      title: meta.title,
      downloadedAt: meta.downloadedAt,
      tileCount: await _countTiles(routeId),
    );
  }

  /// Розмір **тайлів** у МБ (без службових json).
  Future<double> cacheSizeMb(String routeId) async {
    final dir = await _routeDir(routeId);
    if (!await dir.exists()) return 0;
    var bytes = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.png')) {
        bytes += await entity.length();
      }
    }
    return bytes / (1024 * 1024);
  }

  /// [detail] потрібен лише для обчислення області тайлів; на диск пишуться тайли + map_meta.
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
            // Пропускаємо невдалі тайли.
          }
          completed++;
        }),
      );
      yield OfflineMapDownloadProgress(
        completed: completed,
        total: tiles.length,
      );
    }

    await _writeMeta(
      routeId,
      _MapMeta(
        routeId: routeId,
        title: detail.route.title,
        downloadedAt: DateTime.now(),
        tileCount: tiles.length,
      ),
    );

    await marker.writeAsString('1', flush: true);

    final legacy = await _legacyDetailFile(routeId);
    if (await legacy.exists()) {
      await legacy.delete();
    }

    await ensureOfflineRootCached();
  }

  Future<void> deleteOfflineMap(String routeId) async {
    final dir = await _routeDir(routeId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<int> _countTiles(String routeId) async {
    final dir = await _routeDir(routeId);
    if (!await dir.exists()) return 0;
    var count = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.png')) count++;
    }
    return count;
  }

  Future<void> _migrateLegacyDetailIfNeeded(String routeId) async {
    final legacy = await _legacyDetailFile(routeId);
    if (!await legacy.exists()) return;
    final meta = await _metaFile(routeId);
    if (await meta.exists()) {
      await legacy.delete();
      return;
    }
    try {
      final json = jsonDecode(await legacy.readAsString());
      if (json is Map) {
        final route = json['route'];
        final title = route is Map
            ? route['title']?.toString() ?? 'Офлайн-карта'
            : 'Офлайн-карта';
        await _writeMeta(
          routeId,
          _MapMeta(
            routeId: routeId,
            title: title,
            downloadedAt: DateTime.now(),
          ),
        );
      }
    } catch (_) {
      await _writeMeta(
        routeId,
        _MapMeta(routeId: routeId, title: 'Офлайн-карта'),
      );
    }
    await legacy.delete();
  }

  Future<_MapMeta?> _readMeta(String routeId) async {
    final file = await _metaFile(routeId);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      final m = Map<String, dynamic>.from(json);
      return _MapMeta(
        routeId: m['route_id']?.toString() ?? routeId,
        title: m['title']?.toString() ?? 'Офлайн-карта',
        downloadedAt: m['downloaded_at'] != null
            ? DateTime.tryParse(m['downloaded_at'].toString())
            : null,
        tileCount: (m['tile_count'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeMeta(String routeId, _MapMeta meta) async {
    final file = await _metaFile(routeId);
    await file.writeAsString(
      jsonEncode({
        'route_id': meta.routeId,
        'title': meta.title,
        'downloaded_at': meta.downloadedAt?.toIso8601String(),
        'tile_count': meta.tileCount,
        'min_zoom': minZoom,
        'max_zoom': maxZoom,
      }),
      flush: true,
    );
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
}

class _MapMeta {
  final String routeId;
  final String title;
  final DateTime? downloadedAt;
  final int tileCount;

  _MapMeta({
    required this.routeId,
    required this.title,
    this.downloadedAt,
    this.tileCount = 0,
  });
}
