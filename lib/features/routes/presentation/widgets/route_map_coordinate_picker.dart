import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/map/map_overlay_controls.dart';
import '../../../../core/map/map_tile_style.dart';

class RouteMapReferencePoint {
  const RouteMapReferencePoint({
    required this.position,
    required this.label,
    this.pointType = 'viewpoint',
  });

  final LatLng position;
  final String label;
  final String pointType;
}

class RouteMapCoordinatePickerScreen extends StatefulWidget {
  const RouteMapCoordinatePickerScreen({
    super.key,
    this.initialCenter,
    this.initialSelection,
    this.existingPoints = const [],
  });

  final LatLng? initialCenter;
  final LatLng? initialSelection;
  final List<RouteMapReferencePoint> existingPoints;

  static const _defaultCenter = LatLng(48.1588, 24.4671);

  static Future<LatLng?> show(
    BuildContext context, {
    LatLng? initialCenter,
    LatLng? initialSelection,
    List<RouteMapReferencePoint> existingPoints = const [],
  }) {
    return Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => RouteMapCoordinatePickerScreen(
          initialCenter: initialCenter,
          initialSelection: initialSelection,
          existingPoints: existingPoints,
        ),
      ),
    );
  }

  @override
  State<RouteMapCoordinatePickerScreen> createState() =>
      _RouteMapCoordinatePickerScreenState();
}

class _RouteMapCoordinatePickerScreenState
    extends State<RouteMapCoordinatePickerScreen> {
  late final MapController _mapController;
  LatLng? _selection;
  MapTileStyle _mapTileStyle = MapTileStyle.standard;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selection = widget.initialSelection;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitToVisiblePoints());
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  LatLng get _mapCenter =>
      widget.initialCenter ??
      widget.initialSelection ??
      widget.existingPoints.firstOrNull?.position ??
      _defaultCenter;

  static const _defaultCenter = RouteMapCoordinatePickerScreen._defaultCenter;

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() => _selection = point);
  }

  void _confirm() {
    final picked = _selection;
    if (picked == null) return;
    Navigator.of(context).pop(picked);
  }

  void _fitToVisiblePoints() {
    final pts = <LatLng>[
      ...widget.existingPoints.map((p) => p.position),
      if (_selection != null) _selection!,
    ];
    if (pts.isEmpty) return;
    try {
      if (pts.length == 1) {
        _mapController.move(pts.first, 14);
        return;
      }
      final bounds = LatLngBounds.fromPoints(pts);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.only(
            left: 40,
            right: 40,
            top: 72,
            bottom: 160,
          ),
        ),
      );
    } catch (_) {
      _mapController.move(pts.first, 13);
    }
  }

  Color _colorForReference(RouteMapReferencePoint p) {
    return switch (p.pointType) {
      'start' => const Color(0xFF1565C0),
      'finish' => const Color(0xFFC62828),
      _ => const Color(0xFF757575),
    };
  }

  IconData _iconForReference(RouteMapReferencePoint p) {
    return switch (p.pointType) {
      'start' => Icons.flag_outlined,
      'finish' => Icons.sports_score_outlined,
      _ => Icons.location_on_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    final existing = widget.existingPoints;
    final hasExisting = existing.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Точка на карті'),
        actions: [
          TextButton(
            onPressed: selection == null ? null : _confirm,
            child: const Text('Готово'),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: selection != null || hasExisting ? 14 : 10,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: _mapTileStyle.urlTemplate,
                userAgentPackageName: 'com.example.hiking_app',
                maxZoom: onlineMapTileMaxZoom(_mapTileStyle),
              ),
              if (_mapTileStyle == MapTileStyle.terrain)
                const SimpleAttributionWidget(
                  source: Text(openTopoMapAttribution),
                  alignment: Alignment.bottomLeft,
                ),
              if (existing.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: existing.map((p) => p.position).toList(),
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.45),
                      strokeWidth: 3,
                    ),
                  ],
                ),
              if (existing.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final ref in existing)
                      Marker(
                        point: ref.position,
                        width: _ReferenceMapMarker.width,
                        height: _ReferenceMapMarker.height,
                        alignment: Alignment.bottomCenter,
                        child: IgnorePointer(
                          child: _ReferenceMapMarker(
                            label: ref.label,
                            color: _colorForReference(ref),
                            icon: _iconForReference(ref),
                          ),
                        ),
                      ),
                  ],
                ),
              if (selection != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: selection,
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.place,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          MapControlsOverlay(
            mapController: _mapController,
            style: _mapTileStyle,
            onToggleStyle: () =>
                setState(() => _mapTileStyle = _mapTileStyle.toggled),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasExisting)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Кольорові мітки — уже додані точки (лише перегляд). '
                          'Торкніться карти, щоб змінити поточну точку.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            height: 1.35,
                          ),
                        ),
                      ),
                    Text(
                      selection == null
                          ? 'Торкніться карти, щоб обрати точку'
                          : '${selection.latitude.toStringAsFixed(6)}, '
                              '${selection.longitude.toStringAsFixed(6)}',
                      style: TextStyle(
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: selection == null ? null : _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Підтвердити'),
                    ),
                  ],
                ),
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceMapMarker extends StatelessWidget {
  const _ReferenceMapMarker({
    required this.label,
    required this.color,
    required this.icon,
  });

  static const double width = 80;
  static const double height = 58;
  static const double _iconSize = 32;
  static const double _labelBandHeight = 22;

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            height: _labelBandHeight,
            width: width,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: _iconSize,
            height: _iconSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(icon, color: Colors.white, size: 17),
            ),
          ),
        ],
      ),
    );
  }
}
