import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/route_detail.dart';
import 'routes_provider.dart';

final routeOfflineStatusProvider =
    FutureProvider.family<bool, String>((ref, routeId) async {
  final local =
      await ref.watch(offlineMapServiceProvider).hasOfflineMap(routeId);
  if (local) return true;
  return ref.watch(routesRepositoryProvider).isRouteOffline(routeId);
});

final offlineRoutesProvider = FutureProvider<List<RouteDetail>>((ref) async {
  final service = ref.read(offlineMapServiceProvider);
  final local = await service.listDownloadedRoutes();
  final byId = {for (final detail in local) detail.route.id: detail};

  try {
    final remoteRoutes =
        await ref.read(routesRepositoryProvider).getOfflineRoutesFromServer();
    for (final route in remoteRoutes) {
      if (byId.containsKey(route.id)) continue;
      final cached = await service.loadCachedRouteDetail(route.id);
      byId[route.id] = cached ??
          RouteDetail(
            route: route,
            waypoints: const [],
          );
    }
  } catch (_) {}

  final routes = byId.values.toList();
  routes.sort(
    (a, b) => a.route.title.toLowerCase().compareTo(
          b.route.title.toLowerCase(),
        ),
  );
  return routes;
});