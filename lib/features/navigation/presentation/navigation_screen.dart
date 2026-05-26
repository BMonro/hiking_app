import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/map/map_overlay_controls.dart';
import '../../../core/map/map_tile_style.dart';
import '../../../core/network/network_status_provider.dart';
import '../../routes/domain/route_detail.dart';
import '../../routes/presentation/routes_provider.dart';
import '../data/offline_map_service.dart';
import '../data/offline_tile_provider.dart';
import '../domain/offline_route_path.dart';
import '../data/overpass_poi_repository.dart';
import '../data/routing_repository.dart';
import '../domain/hike_qualification.dart';
import '../domain/hike_session_summary.dart';
import '../domain/map_poi.dart';
import 'navigation_complete_dialog.dart';

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
    locationSettings: _navigationLocationSettings(),
  );
});

LocationSettings _navigationLocationSettings() {
  const filter = 4;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: filter,
        intervalDuration: const Duration(seconds: 2),
      );
    case TargetPlatform.iOS:
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: filter,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
      );
    default:
      return LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: filter,
      );
  }
}

class NavigationScreen extends ConsumerStatefulWidget {
  final String? routeIdToFollow;

  final bool forceOfflineNavigation;

  const NavigationScreen({
    super.key,
    this.routeIdToFollow,
    this.forceOfflineNavigation = false,
  });

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

  MapTileStyle _mapTileStyle = MapTileStyle.standard;

  List<LatLng>? _routePoints;

  List<LatLng>? _navWaypoints;
  bool _routeLoading = false;
  bool _pickStartOnMap = false;
  LatLng? _routeDestination;
  LatLng? _pickedRouteStart;

  bool _routeNavActive = false;
  int _routeProgressIndex = 0;

  RouteDetail? _followedRouteDetail;
  DateTime? _navSessionStartedAt;
  double? _navSessionTotalMeters;
  bool _completionHandled = false;

  bool _isRerouting = false;
  DateTime? _lastRerouteAt;
  int _offRouteStreak = 0;

  OfflineTileProvider? _offlineTileProvider;

  bool _offlineOnlyNav = false;
  String? _offlineRouteTitle;

  static const double _finishRadiusM = 80;
  static const double _offRouteThresholdM = 45;
  static const double _offRouteRerouteImmediatelyM = 75;
  static const Duration _rerouteCooldown = Duration(seconds: 25);

  static const double _minGpsMoveForProgressM = 5;

  static const double _minAlongRouteAdvanceM = 4;

  static const double _maxGpsJumpM = 120;

  static const Duration _stationaryGap = Duration(seconds: 90);

  static const double _navFollowZoom = 17;

  double _progressAlongRouteM = 0;

  double _liveAlongRouteM = 0;
  int _liveRouteSegmentIndex = 0;

  double _sessionGpsOdometerM = 0;

  LatLng? _lastAcceptedGpsForProgress;
  LatLng? _lastOdometerGpsPosition;

  Duration _movingDuration = Duration.zero;
  DateTime? _movingSegmentStart;
  DateTime? _lastMovementAt;
  bool _gpsQualityWarned = false;

  double get _followZoom =>
      _offlineOnlyNav ? OfflineMapService.maxZoom.toDouble() : _navFollowZoom;

  LatLng _mapCenterForFollow(LatLng user, List<LatLng> route, int progressIdx) {
    if (!_offlineOnlyNav) return user;
    final idx = progressIdx.clamp(0, route.length - 1);
    return route[idx];
  }

  void _warnIfGpsFarFromRoute(
      LatLng user, List<LatLng> route, int progressIdx) {
    if (!_offlineOnlyNav || !mounted) return;
    const dist = Distance();
    final onRoute = route[progressIdx.clamp(0, route.length - 1)];
    final meters = dist.as(LengthUnit.Meter, user, onRoute);
    if (meters > 1500) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'GPS далеко від маршруту (~${(meters / 1000).toStringAsFixed(1)} км). '
            'Офлайн-карта показує лише зону маршруту. ',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  static const LatLng _defaultCenter = LatLng(48.1588, 24.4671);

  @override
  void initState() {
    super.initState();
    final id = widget.routeIdToFollow?.trim();
    if (id != null && id.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.forceOfflineNavigation) {
          _loadOfflineRoutePackage(id);
        } else {
          _loadRouteFromDatabase(id);
        }
      });
    }
  }

  Future<void> _loadRouteFromDatabase(String routeId) async {
    setState(() => _routeLoading = true);
    try {
      final offlineService = ref.read(offlineMapServiceProvider);
      RouteDetail? detail;
      try {
        detail = await ref
            .read(routeDetailProvider(routeId).future)
            .timeout(const Duration(seconds: 6));
      } catch (_) {
        detail = null;
      }

      if (!mounted) return;
      if (detail == null) {
        final offlinePath = await offlineService.loadOfflinePath(routeId);
        if (offlinePath != null && offlinePath.isValid) {
          await _enterOfflineNavigation(
            routeId: routeId,
            offlinePath: offlinePath,
            offlineService: offlineService,
          );
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Маршрут недоступний без інтернету. Завантажте офлайн-пакет на екрані маршруту.',
            ),
          ),
        );
        setState(() => _routeLoading = false);
        return;
      }

      await _activateOfflineTilesIfNeeded(routeId, offlineService);

      final waypointPositions =
          detail.waypoints.map((w) => w.position).toList();

      List<LatLng>? pts;

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
              'Немає лінії маршруту. Додайте маршрут у редакторі.',
            ),
          ),
        );
        setState(() => _routeLoading = false);
        return;
      }

      final routePts = pts;

      setState(() {
        _followedRouteDetail = detail;
        _routePoints = routePts;
        _navWaypoints = waypointPositions.length >= 2
            ? waypointPositions
            : [routePts.first, routePts.last];
        _routeLoading = false;
        _routeNavActive = false;
        _routeProgressIndex = 0;
        _resetNavSession();
        _resetRerouteState();
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

  Future<void> _loadOfflineRoutePackage(String routeId) async {
    setState(() => _routeLoading = true);
    try {
      final offlineService = ref.read(offlineMapServiceProvider);
      final hasOfflinePackage = await offlineService.hasOfflineMap(routeId);
      final offlinePath = await offlineService.loadOfflinePath(routeId);

      if (!hasOfflinePackage || offlinePath == null || !offlinePath.isValid) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              offlinePath != null
                  ? 'Збережений шлях пошкоджено. Завантажте офлайн-пакет знову.'
                  : 'Офлайн-пакет не знайдено.',
            ),
          ),
        );
        setState(() => _routeLoading = false);
        return;
      }

      await _enterOfflineNavigation(
        routeId: routeId,
        offlinePath: offlinePath,
        offlineService: offlineService,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _routeLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не вдалося завантажити офлайн-маршрут: $e')),
      );
    }
  }

  Future<void> _enterOfflineNavigation({
    required String routeId,
    required OfflineRoutePath offlinePath,
    required OfflineMapService offlineService,
  }) async {
    await _activateOfflineTilesIfNeeded(
      routeId,
      offlineService,
      offlineOnly: true,
    );
    if (!mounted) return;

    final routePts = offlinePath.polyline;
    final waypointPositions = offlinePath.waypoints.length >= 2
        ? offlinePath.waypoints.map((w) => w.position).toList()
        : <LatLng>[];
    final navWps = waypointPositions.length >= 2
        ? waypointPositions
        : [routePts.first, routePts.last];

    setState(() {
      _offlineOnlyNav = true;
      _offlineRouteTitle = offlinePath.title;
      _followedRouteDetail = null;
      _routePoints = routePts;
      _navWaypoints = navWps;
      _routeLoading = false;
      _routeNavActive = false;
      _routeProgressIndex = 0;
      _showPoiLayer = false;
      _pois = [];
      _poiLoading = false;
      _resetNavSession();
      _resetRerouteState();
    });
    _fitRouteOnMap();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Офлайн-режим: ${offlinePath.title}'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _activateOfflineTilesIfNeeded(
    String routeId,
    OfflineMapService offlineService, {
    bool offlineOnly = false,
  }) async {
    if (!await offlineService.hasOfflineMap(routeId)) return;
    await offlineService.ensureOfflineRootCached();
    if (!mounted) return;
    _offlineTileProvider?.dispose();
    _offlineTileProvider = OfflineTileProvider(
      routeId: routeId,
      offlineMapService: offlineService,
      offlineOnly: offlineOnly,
    );
    setState(() => _mapTileStyle = MapTileStyle.standard);
  }

  @override
  void dispose() {
    _poiDebounce?.cancel();
    _offlineTileProvider?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _clearRoute() {
    if (_navSessionStartedAt != null && !_completionHandled) {
      _handleNavigationEnd(reachedFinish: _isNearRouteFinish());
    }
    setState(() {
      _routePoints = null;
      _navWaypoints = null;
      _pickedRouteStart = null;
      _routeDestination = null;
      _pickStartOnMap = false;
      _routeNavActive = false;
      _routeProgressIndex = 0;
      _followedRouteDetail = null;
      _offlineOnlyNav = false;
      _offlineRouteTitle = null;
      _resetNavSession();
      _resetRerouteState();
    });
  }

  void _resetNavSession() {
    _navSessionStartedAt = null;
    _navSessionTotalMeters = null;
    _completionHandled = false;
    _progressAlongRouteM = 0;
    _liveAlongRouteM = 0;
    _liveRouteSegmentIndex = 0;
    _sessionGpsOdometerM = 0;
    _lastAcceptedGpsForProgress = null;
    _lastOdometerGpsPosition = null;
    _movingDuration = Duration.zero;
    _movingSegmentStart = null;
    _lastMovementAt = null;
    _gpsQualityWarned = false;
  }

  double _minMoveForPosition(Position pos) {
    if (!pos.accuracy.isFinite || pos.accuracy <= 0) {
      return _minGpsMoveForProgressM;
    }
    if (pos.accuracy <= 15) return 5;
    if (pos.accuracy <= 25) return 7;
    return math.max(_minGpsMoveForProgressM, pos.accuracy * 0.9);
  }

  double _minAlongRouteAdvanceFor(Position pos) {
    if (pos.accuracy.isFinite && pos.accuracy <= 18) return 2;
    if (pos.accuracy.isFinite && pos.accuracy <= 30) return 3;
    return _minAlongRouteAdvanceM;
  }

  bool _isDeviceLikelyMoving(Position pos) {
    if (pos.speed >= 0 && pos.speed < 0.5) return false;
    return true;
  }

  void _flushMovingDuration() {
    if (_movingSegmentStart == null || _lastMovementAt == null) return;
    _movingDuration += _lastMovementAt!.difference(_movingSegmentStart!);
    _movingSegmentStart = null;
  }

  void _registerGpsMovement() {
    final now = DateTime.now();
    if (_movingSegmentStart == null) {
      _movingSegmentStart = now;
    } else if (_lastMovementAt != null &&
        now.difference(_lastMovementAt!) > _stationaryGap) {
      _movingDuration += _lastMovementAt!.difference(_movingSegmentStart!);
      _movingSegmentStart = now;
    }
    _lastMovementAt = now;
  }

  bool _isGpsReadingReliable(Position pos, double segmentM) {
    if (!_isDeviceLikelyMoving(pos)) return false;
    if (!pos.accuracy.isFinite || pos.accuracy <= 0) return true;
    if (pos.accuracy > 20 && segmentM < pos.accuracy * 0.85) return false;
    return pos.accuracy <= math.max(segmentM * 2.5, 15);
  }

  void _maybeWarnPoorGps(Position pos) {
    if (_gpsQualityWarned || !pos.accuracy.isFinite || pos.accuracy <= 25) {
      return;
    }
    _gpsQualityWarned = true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Неточний GPS (±${pos.accuracy.round()} м). ',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _updateGpsOdometer(LatLng user, Position pos) {
    final last = _lastOdometerGpsPosition;
    if (last == null) {
      _lastOdometerGpsPosition = user;
      return;
    }
    final dist = const Distance();
    final d = dist.as(LengthUnit.Meter, last, user);
    final minMove = _minMoveForPosition(pos);
    if (d < minMove || d > _maxGpsJumpM) return;
    if (!_isGpsReadingReliable(pos, d)) return;
    _sessionGpsOdometerM += d;
    _lastOdometerGpsPosition = user;
    _registerGpsMovement();
  }

  ({LatLng point, double t, double distM}) _closestPointOnSegment(
    LatLng p,
    LatLng a,
    LatLng b,
  ) {
    final dist = const Distance();
    final total = dist.as(LengthUnit.Meter, a, b);
    if (total < 1) {
      return (point: a, t: 0, distM: dist.as(LengthUnit.Meter, p, a));
    }

    const latScale = 111320.0;
    final lonScale =
        111320.0 * math.cos((a.latitude + b.latitude) * math.pi / 360);

    final ax = a.longitude * lonScale;
    final ay = a.latitude * latScale;
    final bx = b.longitude * lonScale;
    final by = b.latitude * latScale;
    final px = p.longitude * lonScale;
    final py = p.latitude * latScale;

    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 <= 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);

    final closest = LatLng(
      (ay + t * dy) / latScale,
      (ax + t * dx) / lonScale,
    );
    return (point: closest, t: t, distM: dist.as(LengthUnit.Meter, p, closest));
  }

  ({
    int segmentIndex,
    double alongRouteM,
    double offRouteM,
  }) _projectOntoRouteForward(
    LatLng user,
    List<LatLng> route,
    int minSegIdx,
  ) {
    final start = minSegIdx.clamp(0, route.length - 2);
    final dist = const Distance();
    var bestDist = double.infinity;
    var bestSeg = start;
    var bestT = 0.0;

    for (var i = start; i < route.length - 1; i++) {
      final c = _closestPointOnSegment(user, route[i], route[i + 1]);
      if (c.distM < bestDist) {
        bestDist = c.distM;
        bestSeg = i;
        bestT = c.t;
      }
    }

    var along = 0.0;
    for (var i = 0; i < bestSeg; i++) {
      along += dist.as(LengthUnit.Meter, route[i], route[i + 1]);
    }
    along +=
        dist.as(LengthUnit.Meter, route[bestSeg], route[bestSeg + 1]) * bestT;

    return (
      segmentIndex: bestSeg,
      alongRouteM: along,
      offRouteM: bestDist.isFinite ? bestDist : 0,
    );
  }

  void _updateAlongRouteProgress(LatLng user, Position pos) {
    final pts = _routePoints;
    if (pts == null || pts.length < 2) return;

    final lastGps = _lastAcceptedGpsForProgress;
    if (lastGps != null) {
      final gpsMove = const Distance().as(LengthUnit.Meter, lastGps, user);
      if (gpsMove < _minMoveForPosition(pos)) return;
      if (!_isGpsReadingReliable(pos, gpsMove)) return;
    }

    final proj = _projectOntoRouteForward(user, pts, _routeProgressIndex);
    if (proj.alongRouteM <=
        _progressAlongRouteM + _minAlongRouteAdvanceFor(pos)) {
      return;
    }

    _lastAcceptedGpsForProgress = user;
    _progressAlongRouteM = proj.alongRouteM;
    _routeProgressIndex = proj.segmentIndex;
  }

  void _updateLiveRouteProgress(LatLng user, List<LatLng> pts, Position pos) {
    final proj = _projectOntoRouteForward(user, pts, _liveRouteSegmentIndex);
    var targetAlong = proj.alongRouteM;

    if (pos.accuracy.isFinite && pos.accuracy > 25) {
      final maxStep = math.min(pos.accuracy * 0.5, 18);
      targetAlong = math.min(targetAlong, _liveAlongRouteM + maxStep);
    }

    if (targetAlong <= _liveAlongRouteM) return;

    _liveAlongRouteM = targetAlong;
    _liveRouteSegmentIndex = proj.segmentIndex;
    _routeProgressIndex = proj.segmentIndex;
  }

  LatLng _interpolateLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  ({List<LatLng> passed, List<LatLng> remaining}) _splitRouteAtMeters(
    List<LatLng> pts,
    double alongM,
  ) {
    if (pts.length < 2 || alongM <= 0) {
      return (passed: <LatLng>[], remaining: pts);
    }
    final dist = const Distance();
    var acc = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      final segLen = dist.as(LengthUnit.Meter, pts[i], pts[i + 1]);
      if (acc + segLen >= alongM) {
        final t = segLen > 0 ? ((alongM - acc) / segLen).clamp(0.0, 1.0) : 0.0;
        final split = _interpolateLatLng(pts[i], pts[i + 1], t);
        return (
          passed: [...pts.sublist(0, i + 1), split],
          remaining: [split, ...pts.sublist(i + 1)],
        );
      }
      acc += segLen;
    }
    return (passed: pts, remaining: [pts.last]);
  }

  double _remainingOnRoute(List<LatLng> pts) {
    return math.max(0, _routeLengthMeters(pts) - _liveAlongRouteM);
  }

  double _remainingForStats(List<LatLng> pts) {
    return math.max(0, _routeLengthMeters(pts) - _progressAlongRouteM);
  }

  double _sessionTraveledMeters(List<LatLng> pts) {
    final routeBased = math.max(
      0.0,
      (_navSessionTotalMeters ?? _routeLengthMeters(pts)) -
          _remainingForStats(pts),
    );
    if (_sessionGpsOdometerM >= 15) return _sessionGpsOdometerM;
    return routeBased;
  }

  void _resetRerouteState() {
    _isRerouting = false;
    _lastRerouteAt = null;
    _offRouteStreak = 0;
  }

  double _routeLengthMeters(List<LatLng> pts) {
    if (pts.length < 2) return 0;
    final dist = const Distance();
    var sum = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      sum += dist.as(LengthUnit.Meter, pts[i], pts[i + 1]);
    }
    return sum;
  }

  bool _isNearRouteFinish() {
    final pts = _routePoints;
    if (pts == null || pts.length < 2) return false;
    return _remainingOnRoute(pts) <= _finishRadiusM;
  }

  void _stopRouteNavigation() {
    _handleNavigationEnd(reachedFinish: _isNearRouteFinish());
  }

  Future<void> _handleNavigationEnd({required bool reachedFinish}) async {
    if (_completionHandled) return;

    final startedAt = _navSessionStartedAt;
    final pts = _routePoints;
    if (startedAt == null || pts == null || pts.length < 2) {
      setState(() => _routeNavActive = false);
      _resetNavSession();
      return;
    }

    _flushMovingDuration();
    final traveledM = _sessionTraveledMeters(pts);
    final wallDuration = DateTime.now().difference(startedAt);
    final duration = _movingDuration >= const Duration(seconds: 30)
        ? _movingDuration
        : wallDuration;

    final qualifies = HikeQualification.qualifiesFromMeters(
      traveledM: traveledM,
      duration: duration,
      reachedFinish: reachedFinish,
    );

    _completionHandled = true;
    if (mounted) {
      setState(() => _routeNavActive = false);
    }

    if (!qualifies) {
      _resetNavSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Похід занадто короткий (${HikeQualification.requirementHint}). '
              'Запис у журнал і досягнення не нараховано.',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    final route = _followedRouteDetail?.route;
    final title = route?.title ??
        _offlineRouteTitle ??
        'Похід ${startedAt.day}.${startedAt.month}.${startedAt.year}';
    final distanceKm = traveledM / 1000;
    final durationHours = duration.inSeconds / 3600.0;

    final summary = HikeSessionSummary(
      routeId: widget.routeIdToFollow ?? route?.id,
      title: title,
      distanceKm: distanceKm,
      durationHours: durationHours,
      suggestedAscentM: route?.ascentM,
      reachedFinish: reachedFinish,
    );

    _resetNavSession();

    if (!mounted) return;
    await showHikeCompletionFlow(context, summary);
  }

  void _checkAutoRouteCompletion() {
    if (!_routeNavActive || _completionHandled) return;
    if (_isNearRouteFinish()) {
      _handleNavigationEnd(reachedFinish: true);
    }
  }

  Future<void> _startRouteNavigation() async {
    final pts = _routePoints;
    if (pts == null || pts.length < 2) return;

    setState(() {
      _routeNavActive = true;
      _routeProgressIndex = 0;
      _progressAlongRouteM = 0;
      _liveAlongRouteM = 0;
      _liveRouteSegmentIndex = 0;
      _sessionGpsOdometerM = 0;
      _lastAcceptedGpsForProgress = null;
      _lastOdometerGpsPosition = null;
      _movingDuration = Duration.zero;
      _movingSegmentStart = null;
      _lastMovementAt = null;
      _navSessionStartedAt = DateTime.now();
      _navSessionTotalMeters = _routeLengthMeters(pts);
      _completionHandled = false;
    });

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      if (!mounted || !_routeNavActive) return;
      final user = LatLng(pos.latitude, pos.longitude);
      final proj = _projectOntoRouteForward(user, pts, 0);
      setState(() {
        _routeProgressIndex = proj.segmentIndex;
        _liveRouteSegmentIndex = proj.segmentIndex;
        _progressAlongRouteM = proj.alongRouteM;
        _liveAlongRouteM = proj.alongRouteM;
        _lastAcceptedGpsForProgress = user;
        _lastOdometerGpsPosition = user;
      });
      _maybeWarnPoorGps(pos);
      _warnIfGpsFarFromRoute(user, pts, proj.segmentIndex);
      _mapController.move(
        _mapCenterForFollow(user, pts, proj.segmentIndex),
        _followZoom,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Увімкніть GPS і надайте доступ, щоб почати навігацію.',
            ),
          ),
        );
      }
      setState(() => _routeNavActive = false);
    }
  }

  String _remainingRouteLabel() {
    final pts = _routePoints;
    if (pts == null || pts.length < 2) return '';
    if (_isRerouting) return 'Перебудова маршруту…';
    if (_routeNavActive) {
      final offM = _distanceToRouteAhead(
        _lastKnownUserPosition,
        pts,
        _routeProgressIndex,
      );
      if (offM >= _offRouteThresholdM) {
        return 'Ви поза маршрутом (~${offM.round()} м) — оновлюємо шлях';
      }
    }
    final m = _remainingOnRoute(pts);
    if (m >= 1000) return '~ ${(m / 1000).toStringAsFixed(1)} км залишилось';
    if (m <= 0) return 'Фініш поруч';
    return '~ ${m.round()} м залишилось';
  }

  LatLng? _lastKnownUserPosition;

  double _distanceToRouteAhead(
    LatLng? user,
    List<LatLng> route,
    int minIdx,
  ) {
    if (user == null || route.length < 2) return 0;
    final start = minIdx.clamp(0, route.length - 2);
    var minD = double.infinity;
    for (var i = start; i < route.length - 1; i++) {
      minD = math.min(
        minD,
        _pointToSegmentMeters(user, route[i], route[i + 1]),
      );
    }
    return minD.isFinite ? minD : 0;
  }

  double _pointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    return _closestPointOnSegment(p, a, b).distM;
  }

  int _nearestIndexOnRoute(LatLng point, List<LatLng> route) {
    final dist = const Distance();
    var bestIdx = 0;
    var bestD = double.infinity;
    for (var i = 0; i < route.length; i++) {
      final d = dist.as(LengthUnit.Meter, point, route[i]);
      if (d < bestD) {
        bestD = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  List<LatLng> _remainingNavWaypoints(List<LatLng> polyline) {
    final wps = _navWaypoints;
    if (wps == null || wps.isEmpty) {
      return [polyline.last];
    }

    final remaining = <LatLng>[];
    for (final wp in wps) {
      final idx = _nearestIndexOnRoute(wp, polyline);
      if (idx >= _routeProgressIndex) {
        remaining.add(wp);
      }
    }

    if (remaining.isEmpty) {
      return [wps.last];
    }

    final lastWp = wps.last;
    if (remaining.last != lastWp) {
      remaining.add(lastWp);
    }
    return remaining;
  }

  Future<void> _maybeRerouteFromPosition(LatLng user) async {
    if (_offlineOnlyNav) return;
    if (!_routeNavActive || _isRerouting || _routePoints == null) return;

    final now = DateTime.now();
    if (_lastRerouteAt != null &&
        now.difference(_lastRerouteAt!) < _rerouteCooldown) {
      return;
    }

    final pts = _routePoints!;
    final offM = _distanceToRouteAhead(user, pts, _routeProgressIndex);
    if (offM < _offRouteThresholdM) {
      _offRouteStreak = 0;
      return;
    }

    _offRouteStreak++;
    final shouldReroute =
        offM >= _offRouteRerouteImmediatelyM || _offRouteStreak >= 2;
    if (!shouldReroute) return;

    var targets = _remainingNavWaypoints(pts);
    if (targets.isEmpty) return;

    final dist = const Distance();
    targets = [
      for (final t in targets)
        if (dist.as(LengthUnit.Meter, user, t) > 25) t,
    ];
    if (targets.isEmpty) {
      targets = [_remainingNavWaypoints(pts).last];
    }

    _isRerouting = true;
    _offRouteStreak = 0;
    if (mounted) setState(() {});

    try {
      final newRoute = await _routingRepo.fetchHikingRouteThrough([
        user,
        ...targets,
      ]);

      if (!mounted || !_routeNavActive || newRoute.length < 2) return;

      final traveledBeforeReroute = _sessionTraveledMeters(pts);
      setState(() {
        _routePoints = newRoute;
        _routeProgressIndex = 0;
        _liveRouteSegmentIndex = 0;
        _progressAlongRouteM = 0;
        _liveAlongRouteM = 0;
        _lastAcceptedGpsForProgress = null;
        _navSessionTotalMeters =
            traveledBeforeReroute + _routeLengthMeters(newRoute);
        _lastRerouteAt = now;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Маршрут перебудовано з вашої позиції'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не вдалося перебудувати маршрут. Перевірте інтернет.',
            ),
          ),
        );
      }
    } finally {
      _isRerouting = false;
      if (mounted) setState(() {});
    }
  }

  List<Polyline> _routePolylinesForNavigation() {
    final pts = _routePoints!;
    final split = _splitRouteAtMeters(pts, _liveAlongRouteM);
    final passed = split.passed;
    final remaining = split.remaining;

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

  bool _isMapCameraReady(MapCamera camera) {
    final s = camera.nonRotatedSize;
    return s.x > 0 && s.y > 0;
  }

  bool _onlineMapFeaturesEnabled() {
    final hasNetwork = ref.read(hasNetworkProvider).value ?? false;
    return isOnlineOnlyFeatureAvailable(
      hasNetwork: hasNetwork,
      offlineNavigation: _offlineOnlyNav,
    );
  }

  void _schedulePoiReload(MapCamera camera) {
    if (!_showPoiLayer || !_onlineMapFeaturesEnabled()) return;
    if (!_isMapCameraReady(camera)) return;
    _poiDebounce?.cancel();
    _poiDebounce = Timer(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      try {
        final cam = _mapController.camera;
        if (mounted && _isMapCameraReady(cam)) _loadPois(cam);
      } catch (_) {}
    });
  }

  Future<void> _loadPois(MapCamera camera) async {
    if (!_showPoiLayer || !_onlineMapFeaturesEnabled() || !mounted) return;

    if (!_isMapCameraReady(camera)) {
      return;
    }

    if (camera.zoom < 10) {
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

  Future<void> _reloadPoisAfterLayoutReady() async {
    var warnedLowZoom = false;
    for (var i = 0; i < 15; i++) {
      if (!mounted || !_showPoiLayer) return;
      try {
        final cam = _mapController.camera;
        if (!_isMapCameraReady(cam)) {
          await Future<void>.delayed(const Duration(milliseconds: 64));
          continue;
        }
        if (cam.zoom < 10 && mounted && !warnedLowZoom) {
          warnedLowZoom = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Наблизьте карту (зум 10+), щоб завантажити точки інтересу.',
              ),
            ),
          );
        }
        await _loadPois(cam);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 64));
      }
    }
  }

  void _toggleMapTileStyle() {
    if (_offlineTileProvider != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Рельєфна карта недоступна разом із завантаженою офлайн-картою маршруту.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    setState(() => _mapTileStyle = _mapTileStyle.toggled);
  }

  double _tileLayerMaxZoom() {
    if (_offlineOnlyNav || _offlineTileProvider != null) {
      return OfflineMapService.maxZoom.toDouble();
    }
    return onlineMapTileMaxZoom(_mapTileStyle);
  }

  void _togglePoiLayer() {
    final hasNetwork = ref.read(hasNetworkProvider).value ?? false;
    if (!isOnlineOnlyFeatureAvailable(
      hasNetwork: hasNetwork,
      offlineNavigation: _offlineOnlyNav,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Точки інтересу недоступні без інтернету'),
        ),
      );
      return;
    }
    setState(() {
      _showPoiLayer = !_showPoiLayer;
      if (!_showPoiLayer) {
        _pois = [];
        _poiLoading = false;
      }
    });
    if (_showPoiLayer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reloadPoisAfterLayoutReady();
      });
    }
  }

  Future<void> _fetchAndShowRoute(LatLng from, LatLng to) async {
    if (_offlineOnlyNav) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Побудова нового маршруту на карті потребує інтернету',
          ),
        ),
      );
      return;
    }
    setState(() => _routeLoading = true);
    try {
      final points = await _routingRepo.fetchHikingRoute(from, to);
      if (!mounted) return;
      if (points.length < 2) {
        throw StateError('SHORT_ROUTE');
      }
      setState(() {
        _routePoints = points;
        _navWaypoints = [from, to];
        _routeLoading = false;
        _pickStartOnMap = false;
        _resetRerouteState();
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
    return 'Не вдалося побудувати маршрут.';
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
            'Не вдалося отримати місцезнаходження. Увімкніть GPS і надайтедоступ.',
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
    final hasNetwork = ref.watch(hasNetworkProvider).value ?? true;
    final onlineFeatures = isOnlineOnlyFeatureAvailable(
      hasNetwork: hasNetwork,
      offlineNavigation: _offlineOnlyNav,
    );
    ref.listen<AsyncValue<bool>>(hasNetworkProvider, (previous, next) {
      final online = next.value ?? true;
      if (!isOnlineOnlyFeatureAvailable(
        hasNetwork: online,
        offlineNavigation: _offlineOnlyNav,
      )) {
        if (_showPoiLayer || _pois.isNotEmpty || _poiLoading) {
          setState(() {
            _showPoiLayer = false;
            _pois = [];
            _poiLoading = false;
          });
        }
      }
    });

    ref.listen<AsyncValue<Position?>>(locationProvider, (previous, next) {
      next.whenData((pos) {
        if (pos == null) return;
        final user = LatLng(pos.latitude, pos.longitude);
        _lastKnownUserPosition = user;

        if (!_routeNavActive || _routePoints == null) return;
        final pts = _routePoints!;
        _updateLiveRouteProgress(user, pts, pos);
        _updateGpsOdometer(user, pos);
        _updateAlongRouteProgress(user, pos);
        final followIdx = _liveRouteSegmentIndex;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_routeNavActive) return;
          setState(() {});
          _mapController.move(
            _mapCenterForFollow(user, pts, followIdx),
            _followZoom,
          );
          _checkAutoRouteCompletion();
          unawaited(_maybeRerouteFromPosition(user));
        });
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Навігація'),
        actions: [
          if (_offlineOnlyNav)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade700),
                  ),
                  child: Text(
                    'Офлайн',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
                urlTemplate: _mapTileStyle.urlTemplate,
                userAgentPackageName: 'com.example.hiking_app',
                tileProvider: _offlineTileProvider,
                minZoom:
                    _offlineOnlyNav ? OfflineMapService.minZoom.toDouble() : 1,
                maxZoom: _tileLayerMaxZoom(),
              ),
              if (_mapTileStyle == MapTileStyle.terrain &&
                  onlineFeatures &&
                  _offlineTileProvider == null)
                const SimpleAttributionWidget(
                  source: Text(openTopoMapAttribution),
                  alignment: Alignment.bottomLeft,
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
              if (_showPoiLayer && onlineFeatures)
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
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        child: const _UserLocationDot(),
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
                              _routeNavActive ? Icons.navigation : Icons.route,
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
                                if (_routeNavActive) ...[
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
                                  locationAsync.maybeWhen(
                                    data: (pos) {
                                      if (pos == null ||
                                          !pos.accuracy.isFinite ||
                                          pos.accuracy <= 25) {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          kDebugMode
                                              ? 'GPS ±${pos.accuracy.round()} м — '
                                                  'емулятор часто дає похибку'
                                              : 'GPS ±${pos.accuracy.round()} м — '
                                                  'очікуйте на відкритій місцевості',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.orange.shade800,
                                          ),
                                        ),
                                      );
                                    },
                                    orElse: () => const SizedBox.shrink(),
                                  ),
                                ],
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
                                    ? 'Завершити'
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
          if (_routeLoading || _isRerouting)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          color: Color(0xFF2E7D32),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isRerouting
                              ? 'Перебудова маршруту…'
                              : 'Побудова маршруту…',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          MapControlsOverlay(
            mapController: _mapController,
            style: _mapTileStyle,
            onToggleStyle: _toggleMapTileStyle,
            showStyleToggle: onlineFeatures && _offlineTileProvider == null,
            maxZoomCap:
                _offlineOnlyNav ? OfflineMapService.maxZoom.toDouble() : null,
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
                    if (onlineFeatures) ...[
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
                    ],
                    if (onlineFeatures) ...[
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

class _UserLocationDot extends StatelessWidget {
  const _UserLocationDot();

  static const double _size = 28;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment.center,
          radius: 0.55,
          colors: [
            Color(0xFFB9F6CA),
            Color(0xFF66BB6A),
            Color(0xFF1B5E20),
          ],
          stops: [0.0, 0.45, 1.0],
        ),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}
