import '../../../core/api/backend_api.dart';
import '../domain/route_variant.dart';

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
    RouteVariant? chosenRoute,
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
        if (chosenRoute != null)
          'chosen_route': chosenRoute.toChosenRoutePayload(),
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
    bool? isPublic,
    RouteVariant? chosenRoute,
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
        if (isPublic != null) 'is_public': isPublic,
        'points': points,
        if (chosenRoute != null)
          'chosen_route': chosenRoute.toChosenRoutePayload(),
      },
      timeout: const Duration(seconds: 120),
    );
    return data['route_id'].toString();
  }
}
