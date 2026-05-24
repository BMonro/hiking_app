import 'package:latlong2/latlong.dart';

import '../../../core/api/backend_api.dart';
import '../domain/route_variant.dart';
import 'route_variants_local_repository.dart';

class RouteVariantsApi {
  RouteVariantsApi({
    BackendApi? api,
    RouteVariantsLocalRepository? local,
  })  : _api = api ?? BackendApi(),
        _local = local ?? RouteVariantsLocalRepository();

  final BackendApi _api;
  final RouteVariantsLocalRepository _local;

  Future<List<RouteVariant>> fetchVariants(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return const [];

    List<RouteVariant> edge = const [];
    try {
      final data = await _api.invoke(
        'route-hike',
        body: {
          'alternatives': true,
          'waypoints': waypoints
              .map((p) => {'lat': p.latitude, 'lon': p.longitude})
              .toList(),
        },
        timeout: const Duration(seconds: 120),
      );

      final raw = data['variants'] as List? ?? [];
      edge = raw
          .map(
            (v) => RouteVariant.fromJson(Map<String, dynamic>.from(v as Map)),
          )
          .where((v) => v.points.length >= 2)
          .toList();
    } on BackendApiException {

    } catch (_) {}

    if (edge.length >= 2) return edge;

    try {
      final local = await _local.fetchVariants(waypoints);
      if (local.length > edge.length) return local;
    } catch (_) {}

    return edge;
  }
}
