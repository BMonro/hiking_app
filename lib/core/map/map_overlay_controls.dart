import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'map_tile_style.dart';

class MapStyleToggleButton extends StatelessWidget {
  const MapStyleToggleButton({
    super.key,
    required this.style,
    required this.onPressed,
  });

  final MapTileStyle style;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      color: style == MapTileStyle.terrain
          ? const Color(0xFFE8F5E9)
          : Colors.white,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          style == MapTileStyle.terrain ? Icons.terrain : Icons.terrain_outlined,
        ),
        color: style == MapTileStyle.terrain
            ? const Color(0xFF1B5E20)
            : const Color(0xFF2E7D32),
        tooltip: style.toggleTooltip,
      ),
    );
  }
}

class MapZoomControls extends StatelessWidget {
  const MapZoomControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onZoomIn,
            icon: const Icon(Icons.add),
            color: const Color(0xFF2E7D32),
            tooltip: 'Збільшити масштаб',
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
          ),
          Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
          IconButton(
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove),
            color: const Color(0xFF2E7D32),
            tooltip: 'Зменшити масштаб',
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
          ),
        ],
      ),
    );
  }
}

class MapZoomAndStyleControls extends StatelessWidget {
  const MapZoomAndStyleControls({
    super.key,
    required this.mapController,
    required this.style,
    required this.onToggleStyle,
    this.showStyleToggle = true,
    this.maxZoomCap,
  });

  final MapController mapController;
  final MapTileStyle style;
  final VoidCallback onToggleStyle;
  final bool showStyleToggle;
  final double? maxZoomCap;

  void _zoomBy(double delta) {
    try {
    final cam = mapController.camera;
    final minZ = cam.minZoom ?? 1;
    var maxZ = cam.maxZoom ?? 22;
    if (maxZoomCap != null) {
      maxZ = math.min(maxZ, maxZoomCap!);
    }
    final styleCap = style.maxZoom;
    if (styleCap != null) {
      maxZ = math.min(maxZ, styleCap);
    }
    final z = (cam.zoom + delta).clamp(minZ, maxZ);
    if ((z - cam.zoom).abs() < 0.01) return;
    mapController.move(cam.center, z);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MapZoomControls(
          onZoomIn: () => _zoomBy(1),
          onZoomOut: () => _zoomBy(-1),
        ),
        if (showStyleToggle) ...[
          const SizedBox(height: 8),
          MapStyleToggleButton(
            style: style,
            onPressed: onToggleStyle,
          ),
        ],
      ],
    );
  }
}

class MapControlsOverlay extends StatelessWidget {
  const MapControlsOverlay({
    super.key,
    required this.mapController,
    required this.style,
    required this.onToggleStyle,
    this.showStyleToggle = true,
    this.maxZoomCap,
    this.padding = const EdgeInsets.only(top: 8, left: 8),
  });

  final MapController mapController;
  final MapTileStyle style;
  final VoidCallback onToggleStyle;
  final bool showStyleToggle;
  final double? maxZoomCap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      child: SafeArea(
        child: Padding(
          padding: padding,
          child: MapZoomAndStyleControls(
            mapController: mapController,
            style: style,
            onToggleStyle: onToggleStyle,
            showStyleToggle: showStyleToggle,
            maxZoomCap: maxZoomCap,
          ),
        ),
      ),
    );
  }
}

double onlineMapTileMaxZoom(MapTileStyle style, {double? cap}) {
  const defaultMax = 22.0;
  final styleCap = style.maxZoom;
  var maxZ = cap ?? defaultMax;
  if (styleCap != null) {
    maxZ = math.min(maxZ, styleCap);
  }
  return maxZ;
}
