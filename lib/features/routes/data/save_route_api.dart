import '../../../core/api/backend_api.dart';

class SaveRouteApi {
  SaveRouteApi({BackendApi? api}) : _api = api ?? BackendApi();

  final BackendApi _api;

  Future<String> createRoute({
    required String title,
    required String routeType,
    required String description,
    required String difficulty,
    required List<Map<String, dynamic>> points,
    bool isPublic = true,
  }) async {
    final data = await _api.invoke(
      'save-route',
      body: {
        'action': 'create',
        'title': title,
        'route_type': routeType,
        'description': description,
        'difficulty': difficulty,
        'is_public': isPublic,
        'points': points,
      },
      timeout: const Duration(seconds: 120),
    );
    return data['route_id'].toString();
  }

  Future<String> updateRoute({
    required String routeId,
    required String title,
    required String routeType,
    required String description,
    required String difficulty,
    required List<Map<String, dynamic>> points,
  }) async {
    final data = await _api.invoke(
      'save-route',
      body: {
        'action': 'update',
        'route_id': routeId,
        'title': title,
        'route_type': routeType,
        'description': description,
        'difficulty': difficulty,
        'points': points,
      },
      timeout: const Duration(seconds: 120),
    );
    return data['route_id'].toString();
  }
}
