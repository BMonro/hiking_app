import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'offline_map_service.dart';

/// Світло-сірий непрозорий PNG (8×8) — замість прозорого 1×1, який на карті дає артефакти.
final ImageProvider _missingTileImage = MemoryImage(
  Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAADElEQVQIHWMwYGBgAAAABQABh6F1pgAAAABJRU5ErkJggg==',
    ),
  ),
);

class OfflineTileProvider extends TileProvider {
  OfflineTileProvider({
    required this.routeId,
    required this.offlineMapService,
    this.offlineOnly = false,
    NetworkTileProvider? networkProvider,
  }) : _networkProvider = offlineOnly
            ? null
            : (networkProvider ?? NetworkTileProvider());

  final String routeId;
  final OfflineMapService offlineMapService;

  /// Без fallback на OSM — лише локальні тайли (або сірий placeholder).
  final bool offlineOnly;
  final NetworkTileProvider? _networkProvider;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final path = offlineMapService.tileFilePath(
      routeId,
      coordinates.z,
      coordinates.x,
      coordinates.y,
    );
    if (path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        return FileImage(file);
      }
    }
    if (offlineOnly) return _missingTileImage;
    return _networkProvider!.getImage(coordinates, options);
  }

  @override
  Future<void> dispose() async {
    await _networkProvider?.dispose();
    super.dispose();
  }
}
