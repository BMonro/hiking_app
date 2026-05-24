import 'package:latlong2/latlong.dart';

import '../../routes/domain/route_detail.dart';
import 'prepare_offline_api.dart';
import 'routing_repository.dart';

/// Побудова лінії шляху для офлайн-пакета (Edge `prepare-offline-route` або routing).
Future<List<LatLng>> resolveRoutePathPolyline(
  RouteDetail detail,
  RoutingRepository routing,
) async {
  try {
    final poly = await PrepareOfflineApi().preparePolyline(detail.route.id);
    if (poly.length >= 2) return poly;
  } catch (_) {}

  final waypointPositions = detail.waypoints.map((w) => w.position).toList();

  if (waypointPositions.length >= 2) {
    try {
      final routed = await routing.fetchHikingRouteThrough(waypointPositions);
      if (routed.length >= 2) return routed;
    } catch (_) {}
  }

  final poly = detail.polyline;
  if (poly != null && poly.length >= 2) return poly;

  if (waypointPositions.length >= 2) return waypointPositions;

  throw StateError(
    'Немає лінії маршруту. Додайте точки або збережіть geojson у редакторі.',
  );
}
