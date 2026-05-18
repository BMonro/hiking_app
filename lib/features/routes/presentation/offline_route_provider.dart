import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/domain/offline_map_package.dart';
import 'routes_provider.dart';

final routeOfflineStatusProvider =
    FutureProvider.family<bool, String>((ref, routeId) async {
  final local =
      await ref.watch(offlineMapServiceProvider).hasOfflineMap(routeId);
  if (local) return true;
  return ref.watch(routesRepositoryProvider).isRouteOffline(routeId);
});

/// Локально збережені **карти** (тайли), не копії маршрутів.
final offlineMapsProvider = FutureProvider<List<OfflineMapPackage>>((ref) async {
  ref.keepAlive();
  final service = ref.read(offlineMapServiceProvider);
  final local = await service.listOfflineMaps();
  final byId = {for (final m in local) m.routeId: m};

  try {
    final remote =
        await ref.read(routesRepositoryProvider).getOfflineRoutesFromServer();
    for (final route in remote) {
      if (byId.containsKey(route.id)) continue;
      if (await service.hasOfflineMap(route.id)) {
        final pkg = await service.getOfflineMap(route.id);
        if (pkg != null) byId[route.id] = pkg;
      } else {
        byId[route.id] = OfflineMapPackage(
          routeId: route.id,
          title: route.title,
        );
      }
    }
  } catch (_) {}

  final maps = byId.values.toList();
  maps.sort(
    (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
  );
  return maps;
});

/// Зворотна сумісність імені (якщо десь лишилось посилання).
@Deprecated('Use offlineMapsProvider')
final offlineRoutesProvider = offlineMapsProvider;
