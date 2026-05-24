import 'package:latlong2/latlong.dart';

import '../../routes/domain/route_detail.dart';

/// Лінія маршруту для офлайн-навігації (без метаданих маршруту з БД).
class OfflineRoutePath {
  final String routeId;
  final String title;
  final List<LatLng> polyline;
  final List<RouteWaypoint> waypoints;

  const OfflineRoutePath({
    required this.routeId,
    required this.title,
    required this.polyline,
    this.waypoints = const [],
  });

  bool get isValid => polyline.length >= 2;
}
