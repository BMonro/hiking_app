import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/domain/offline_map_package.dart';
import 'routes_provider.dart';

final routeOfflineStatusProvider =
    FutureProvider.family<bool, String>((ref, routeId) async {
  return ref.watch(offlineMapServiceProvider).hasOfflineMap(routeId);
});

final offlineMapsProvider = FutureProvider<List<OfflineMapPackage>>((ref) async {
  ref.keepAlive();
  return ref.read(offlineMapServiceProvider).listOfflineMaps();
});

@Deprecated('Use offlineMapsProvider')
final offlineRoutesProvider = offlineMapsProvider;
