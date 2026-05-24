import 'package:latlong2/latlong.dart';

import '../../../core/api/backend_api.dart';

class PrepareOfflineApi {
  PrepareOfflineApi({BackendApi? api}) : _api = api ?? BackendApi();

  final BackendApi _api;

  Future<List<LatLng>> preparePolyline(String routeId) async {
    final data = await _api.invoke(
      'prepare-offline-route',
      body: {'route_id': routeId},
      timeout: const Duration(seconds: 120),
    );

    final polyRaw = data['polyline'] as List? ?? [];
    return polyRaw
        .map((p) {
          final m = Map<String, dynamic>.from(p as Map);
          return LatLng(
            (m['lat'] as num).toDouble(),
            (m['lon'] as num).toDouble(),
          );
        })
        .where((p) => p.latitude != 0 || p.longitude != 0)
        .toList();
  }
}
