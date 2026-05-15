import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'offline_map_service.dart';

class OfflineTileProvider extends TileProvider {
  OfflineTileProvider({
    required this.routeId,
    required this.offlineMapService,
    NetworkTileProvider? networkProvider,
  }) : _networkProvider = networkProvider ?? NetworkTileProvider();

  final String routeId;
  final OfflineMapService offlineMapService;
  final NetworkTileProvider _networkProvider;

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
    return _networkProvider.getImage(coordinates, options);
  }

  @override
  Future<void> dispose() async {
    await _networkProvider.dispose();
    super.dispose();
  }
}
