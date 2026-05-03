import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../../routes/presentation/routes_provider.dart';
import '../data/overpass_poi_repository.dart';
import '../data/routing_repository.dart';
import '../domain/map_poi.dart';

final locationProvider = StreamProvider<Position?>((ref) async* {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    yield null;
    return;
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      yield null;
      return;
    }
  }

  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    ),
  );
});

class NavigationScreen extends ConsumerStatefulWidget {
  /// Якщо задано — підвантажити збережений маршрут з БД і показати на карті.
  final String? routeIdToFollow;

  const NavigationScreen({super.key, this.routeIdToFollow});

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  final MapController _mapController = MapController();
  final OverpassPoiRepository _poiRepo = OverpassPoiRepository();
  final RoutingRepository _routingRepo = RoutingRepository();

  Timer? _poiDebounce;

  bool _showPoiLayer = false;
  bool _poiLoading = false;
  List<MapPoi> _pois = [];

  List<LatLng>? _routePoints;
  bool _routeLoading = false;
  bool _pickStartOnMap = false;
  LatLng? _routeDestination;
  LatLng? _pickedRouteStart;

  /// Рух уздовж побудованого маршруту (карта слідує за GPS).
  bool _routeNavActive = false;
  int _routeProgressIndex = 0;

  static const double _navFollowZoom = 17;

  // Карпати — початкова позиція карти
  static const LatLng _defaultCenter = LatLng(48.1588, 24.4671);

  @override
  void initState() {
    super.initState();
    final id = widget.routeIdToFollow?.trim();
    if (id != null && id.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadRouteFromDatabase(id);
      });
    }
  }

  Future<void> _loadRouteFromDatabase(String routeId) async {
    setState(() => _routeLoading = true);
    try {
      final detail = await ref.read(routeDetailProvider(routeId).future);
      if (!mounted) return;
      if (detail == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Маршрут не знайдено')),
        );
        setState(() => _routeLoading = false);
        return;
      }

      final waypointPositions =
          detail.waypoints.map((w) => w.position).toList();

      List<LatLng>? pts;

      // Спочатку будуємо шлях по OSM-стежках (важливіше за збережений geojson з прямими).
      if (waypointPositions.length >= 2) {
        try {
          pts = await _routingRepo.fetchHikingRouteThrough(waypointPositions);
        } catch (_) {}
      }

      if (!mounted) return;

      if (pts == null || pts.length < 2) {
        pts = detail.polyline;
      }

      if (pts == null || pts.length < 2) {
        pts = waypointPositions;
      }

      if (pts.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Немає лінії маршруту (geojson або точок). Додайте маршрут у редакторі.',
            ),
          ),
        );
        setState(() => _routeLoading = false);
        return;
      }

      setState(() {
        _routePoints = pts;
        _routeLoading = false;
        _routeNavActive = false;
        _routeProgressIndex = 0;
      });
      _fitRouteOnMap();
    } catch (e) {
      if (!mounted) return;
      setState(() => _routeLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не вдалося завантажити маршрут: $e')),
      );
    }
  }

  @override
  void dispose() {
    _poiDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _clearRoute() {
    setState(() {
      _routePoints = null;
      _pickedRouteStart = null;
      _routeDestination = null;
      _pickStartOnMap = false;
      _routeNavActive = false;
      _routeProgressIndex = 0;
    });
  }

  void _stopRouteNavigation() {
    setState(() {
      _routeNavActive = false;
    });
  }

  Future<void> _startRouteNavigation() async {
    final pts = _routePoints;
    if (pts == null || pts.length < 2) return;

    setState(() {
      _routeNavActive = true;
      _routeProgressIndex = 0;
    });

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      if (!mounted || !_routeNavActive) return;
      final user = LatLng(pos.latitude, pos.longitude);
      final idx = _nearestForwardRouteIndex(user, pts, 0);
      setState(() => _routeProgressIndex = idx);
      _mapController.move(user, _navFollowZoom);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Увімкніть GPS і дозвольте доступ, щоб почати навігацію.',
            ),
          ),
        );
      }
      setState(() => _routeNavActive = false);
    }
  }

  /// Найближча вершина полілінії не раніше за [minIdx] (рух уперед по маршруту).
  int _nearestForwardRouteIndex(
    LatLng user,
    List<LatLng> route,
    int minIdx,
  ) {
    final dist = const Distance();
    var bestIdx = math.min(math.max(0, minIdx), route.length - 1);
    var bestD = dist.as(LengthUnit.Meter, user, route[bestIdx]);
    for (var i = minIdx; i < route.length; i++) {
      final d = dist.as(LengthUnit.Meter, user, route[i]);
      if (d < bestD) {
        bestD = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  double _remainingRouteMeters(List<LatLng> pts, int fromIndex) {
    if (pts.length < 2 || fromIndex >= pts.length - 1) return 0;
    final dist = const Distance();
    var sum = 0.0;
    for (var i = fromIndex; i < pts.length - 1; i++) {
      sum += dist.as(LengthUnit.Meter, pts[i], pts[i + 1]);
    }
    return sum;
  }

  String _remainingRouteLabel() {
    final pts = _routePoints;
    if (pts == null || pts.length < 2) return '';
    final m = _remainingRouteMeters(pts, _routeProgressIndex);
    if (m >= 1000) return '~ ${(m / 1000).toStringAsFixed(1)} км залишилось';
    if (m <= 0) return 'Фініш поруч';
    return '~ ${m.round()} м залишилось';
  }

  /// Пройдений шлях (сірий) і залишок (зелений) під час навігації.
  List<Polyline> _routePolylinesForNavigation() {
    final pts = _routePoints!;
    final idx = _routeProgressIndex.clamp(0, pts.length - 1);
    final passed = pts.sublist(0, idx + 1);
    final remaining = pts.sublist(idx);

    final list = <Polyline>[];
    if (passed.length >= 2) {
      list.add(
        Polyline(
          points: passed,
          strokeWidth: 4,
          color: Colors.grey.shade400,
          borderStrokeWidth: 1,
          borderColor: Colors.white,
        ),
      );
    }
    if (remaining.length >= 2) {
      list.add(
        Polyline(
          points: remaining,
          strokeWidth: 5,
          color: const Color(0xFF2E7D32),
          borderStrokeWidth: 2,
          borderColor: Colors.white,
        ),
      );
    }
    if (list.isEmpty) {
      list.add(
        Polyline(
          points: pts,
          strokeWidth: 5,
          color: const Color(0xFF2E7D32),
          borderStrokeWidth: 2,
          borderColor: Colors.white,
        ),
      );
    }
    return list;
  }

  void _schedulePoiReload(MapCamera camera) {
    if (!_showPoiLayer) return;
    _poiDebounce?.cancel();
    _poiDebounce = Timer(const Duration(milliseconds: 750), () {
      if (mounted) _loadPois(camera);
    });
  }

  Future<void> _loadPois(MapCamera camera) async {
    if (!_showPoiLayer || !mounted) return;

    if (camera.zoom < 11) {
      setState(() {
        _pois = [];
        _poiLoading = false;
      });
      return;
    }

    setState(() => _poiLoading = true);

    try {
      final bounds = camera.visibleBounds;
      final result = await _poiRepo.fetchPoisInBounds(bounds);
      if (!mounted) return;

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Наблизьте карту: область завелика для завантаження точок.',
            ),
          ),
        );
        setState(() {
          _pois = [];
          _poiLoading = false;
        });
        return;
      }

      setState(() {
        _pois = result;
        _poiLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pois = [];
        _poiLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не вдалося завантажити точки. Перевірте інтернет і спробуйте знову.',
          ),
        ),
      );
    }
  }

  void _togglePoiLayer() {
    setState(() {
      _showPoiLayer = !_showPoiLayer;
      if (!_showPoiLayer) {
        _pois = [];
        _poiLoading = false;
      }
    });
    if (_showPoiLayer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final cam = _mapController.camera;
        if (cam.zoom < 11) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Наблизьте карту до рівня зуму 11 або вище, щоб з\'явились точки інтересу.',
              ),
            ),
          );
        }
        _loadPois(cam);
      });
    }
  }

  Future<void> _fetchAndShowRoute(LatLng from, LatLng to) async {
    setState(() => _routeLoading = true);
    try {
      final points = await _routingRepo.fetchHikingRoute(from, to);
      if (!mounted) return;
      if (points.length < 2) {
        throw StateError('SHORT_ROUTE');
      }
      setState(() {
        _routePoints = points;
        _routeLoading = false;
        _pickStartOnMap = false;
      });
      _fitRouteOnMap();
    } catch (e) {
      if (!mounted) return;
      setState(() => _routeLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_routeErrorMessage(e)),
        ),
      );
    }
  }

  String _routeErrorMessage(Object e) {
    final s = e.toString();
    return 'Не вдалося побудувати маршрут (GraphHopper і OSRM). Деталі: $s';
  }

  void _fitRouteOnMap() {
    final pts = _routePoints;
    if (pts == null || pts.isEmpty) return;
    try {
      final bounds = LatLngBounds.fromPoints(pts);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.only(
            left: 40,
            right: 40,
            top: 72,
            bottom: 120,
          ),
        ),
      );
    } catch (_) {
      _mapController.move(pts.first, 13);
    }
  }

  Future<void> _routeFromMyLocation(MapPoi dest) async {
    final to = LatLng(dest.lat, dest.lon);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      final from = LatLng(pos.latitude, pos.longitude);
      setState(() => _pickedRouteStart = null);
      await _fetchAndShowRoute(from, to);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не вдалося отримати місцезнаходження. Увімкніть GPS і дозвольте доступ.',
          ),
        ),
      );
    }
  }

  void _beginPickStartOnMap(MapPoi dest) {
    setState(() {
      _pickStartOnMap = true;
      _routeDestination = LatLng(dest.lat, dest.lon);
      _pickedRouteStart = null;
      _routePoints = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Торкніться карти, щоб обрати точку старту'),
      ),
    );
  }

  void _cancelPickStart() {
    setState(() {
      _pickStartOnMap = false;
      _routeDestination = null;
    });
  }

  void _showRouteStartOptions(MapPoi dest) {
    final title = (dest.name != null && dest.name!.isNotEmpty)
        ? dest.name!
        : MapPoi.labelUk(dest.kind);

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Маршрут',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _routeFromMyLocation(dest);
                },
                icon: const Icon(Icons.my_location),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                label: const Text('З мого місцезнаходження'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _beginPickStartOnMap(dest);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.touch_app),
                label: const Text('Обрати старт на карті'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPoiSheet(MapPoi p) {
    final title = (p.name != null && p.name!.isNotEmpty)
        ? p.name!
        : MapPoi.labelUk(p.kind);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(MapPoi.iconFor(p.kind), color: MapPoi.colorFor(p.kind)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              MapPoi.labelUk(p.kind),
              style: TextStyle(color: Colors.grey[700]),
            ),
            if (p.elevationM != null) ...[
              const SizedBox(height: 6),
              Text(
                'Висота: ${p.elevationM} м',
                style: TextStyle(
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _showRouteStartOptions(p);
                  });
                },
                icon: const Icon(Icons.directions_walk),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                label: const Text('Відправитися'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationAsync = ref.watch(locationProvider);

    ref.listen<AsyncValue<Position?>>(locationProvider, (previous, next) {
      next.whenData((pos) {
        if (!_routeNavActive || pos == null || _routePoints == null) return;
        final pts = _routePoints!;
        final user = LatLng(pos.latitude, pos.longitude);
        final newIdx =
            _nearestForwardRouteIndex(user, pts, _routeProgressIndex);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_routeNavActive) return;
          setState(() => _routeProgressIndex = newIdx);
          _mapController.move(user, _navFollowZoom);
        });
      });
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Навігація')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 12,
              onPositionChanged: (camera, hasGesture) {
                _schedulePoiReload(camera);
              },
              onTap: (tapPosition, point) {
                if (!_pickStartOnMap || _routeDestination == null) return;
                setState(() => _pickedRouteStart = point);
                _fetchAndShowRoute(point, _routeDestination!);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.hiking_app',
              ),
              if (_routePoints != null && _routePoints!.length >= 2)
                PolylineLayer(
                  polylines: _routeNavActive
                      ? _routePolylinesForNavigation()
                      : [
                          Polyline(
                            points: _routePoints!,
                            strokeWidth: 5,
                            color: const Color(0xFF2E7D32),
                            borderStrokeWidth: 2,
                            borderColor: Colors.white,
                          ),
                        ],
                ),
              if (_showPoiLayer)
                MarkerLayer(
                  markers: _pois
                      .map(
                        (p) => Marker(
                          point: LatLng(p.lat, p.lon),
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          child: GestureDetector(
                            onTap: () => _showPoiSheet(p),
                            child: Container(
                              decoration: BoxDecoration(
                                color: MapPoi.colorFor(p.kind)
                                    .withValues(alpha: 0.92),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Icon(
                                MapPoi.iconFor(p.kind),
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              if (_pickedRouteStart != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _pickedRouteStart!,
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.flag,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              locationAsync.when(
                loading: () => const MarkerLayer(markers: []),
                error: (_, __) => const MarkerLayer(markers: []),
                data: (position) {
                  if (position == null) return const MarkerLayer(markers: []);
                  final currentLatLng = LatLng(
                    position.latitude,
                    position.longitude,
                  );
                  return MarkerLayer(
                    markers: [
                      Marker(
                        point: currentLatLng,
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    Colors.black.withValues(alpha: 0.3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.navigation,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          if (_pickStartOnMap)
            Positioned(
              left: 16,
              right: 16,
              bottom: 100,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Оберіть точку старту на карті',
                          style: TextStyle(
                            color: Colors.grey[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _cancelPickStart,
                        child: const Text('Скасувати'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_routePoints != null && _routePoints!.length >= 2)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              _routeNavActive
                                  ? Icons.navigation
                                  : Icons.route,
                              color: const Color(0xFF2E7D32),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _routeNavActive
                                      ? 'Навігація активна'
                                      : 'Маршрут побудовано',
                                  style: TextStyle(
                                    color: Colors.grey[800],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                if (_routeNavActive)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      _remainingRouteLabel(),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            TextButton(
                              onPressed: _routeNavActive
                                  ? _stopRouteNavigation
                                  : _startRouteNavigation,
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF2E7D32),
                              ),
                              child: Text(
                                _routeNavActive
                                    ? 'Зупинити'
                                    : 'Почати навігацію',
                              ),
                            ),
                            TextButton(
                              onPressed: _clearRoute,
                              child: const Text('Очистити'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_routeLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF2E7D32)),
                        SizedBox(height: 16),
                        Text('Побудова маршруту…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                      child: IconButton(
                        onPressed: () => _centerOnLocation(locationAsync),
                        icon: const Icon(Icons.my_location),
                        color: const Color(0xFF2E7D32),
                        tooltip: 'Моя позиція',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(12),
                      color: _showPoiLayer
                          ? const Color(0xFFE8F5E9)
                          : Colors.white,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          IconButton(
                            onPressed: _togglePoiLayer,
                            icon: Icon(
                              _showPoiLayer
                                  ? Icons.interests
                                  : Icons.interests_outlined,
                            ),
                            color: _showPoiLayer
                                ? const Color(0xFF1B5E20)
                                : const Color(0xFF2E7D32),
                            tooltip: 'Точки інтересу',
                          ),
                          if (_poiLoading)
                            const Positioned(
                              right: 6,
                              top: 6,
                              child: SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                      child: IconButton(
                        onPressed: () => context.push('/weather'),
                        icon: const Icon(Icons.wb_sunny_outlined),
                        color: const Color(0xFF2E7D32),
                        tooltip: 'Погода',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _centerOnLocation(AsyncValue<Position?> locationAsync) {
    locationAsync.whenData((position) {
      if (position != null) {
        _mapController.move(
          LatLng(position.latitude, position.longitude),
          15,
        );
      }
    });
  }
}
