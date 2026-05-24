import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/data/offline_map_service.dart';
import '../data/route_ratings_repository.dart';
import '../data/routes_repository.dart';
import '../domain/route_detail.dart';
import '../domain/route_model.dart';
import '../domain/route_rating.dart';

final routesRepositoryProvider = Provider((ref) => RoutesRepository());

final routeRatingsRepositoryProvider =
    Provider((ref) => RouteRatingsRepository());

final offlineMapServiceProvider = Provider((ref) => OfflineMapService());

final searchQueryProvider = StateProvider<String>((ref) => '');
final difficultyFilterProvider = StateProvider<String>((ref) => 'all');

final routeTypeFilterProvider = StateProvider<String>((ref) => 'all');
final durationMaxFilterProvider = StateProvider<double?>((ref) => null);
final ascentMaxFilterProvider = StateProvider<int?>((ref) => null);

final routesProvider = FutureProvider<List<RouteModel>>((ref) async {
  ref.keepAlive();
  final repo = ref.watch(routesRepositoryProvider);
  final search = ref.watch(searchQueryProvider);
  final difficulty = ref.watch(difficultyFilterProvider);
  final routeType = ref.watch(routeTypeFilterProvider);
  final durationMax = ref.watch(durationMaxFilterProvider);
  final ascentMax = ref.watch(ascentMaxFilterProvider);
  return repo.getRoutes(
    search: search,
    difficulty: difficulty,
    routeType: routeType,
    durationMax: durationMax,
    ascentMax: ascentMax,
  );
});

final myPublicRoutesProvider = FutureProvider<List<RouteModel>>((ref) async {
  ref.keepAlive();
  final repo = ref.watch(routesRepositoryProvider);
  return repo.getMyRoutes(isPublic: true);
});

final myPrivateRoutesProvider = FutureProvider<List<RouteModel>>((ref) async {
  ref.keepAlive();
  final repo = ref.watch(routesRepositoryProvider);
  return repo.getMyRoutes(isPublic: false);
});

final routeDetailProvider =
    FutureProvider.family<RouteDetail?, String>((ref, routeId) async {
  final repo = ref.watch(routesRepositoryProvider);
  return repo.getRouteDetail(routeId);
});

final routeReviewsProvider =
    FutureProvider.family<RouteReviewsSummary, String>((ref, routeId) async {
  return ref.watch(routeRatingsRepositoryProvider).fetchForRoute(routeId);
});

final routeSortProvider = StateProvider<String>((ref) => 'newest');

void sortRouteListItems(List<RouteListItem> items, String sort) {
  switch (sort) {
    case 'rating_desc':
      items.sort((a, b) {
        final ac = a.stats?.count ?? 0;
        final bc = b.stats?.count ?? 0;
        if (ac == 0 && bc == 0) return 0;
        if (ac == 0) return 1;
        if (bc == 0) return -1;
        final byRating =
            b.stats!.averageRating.compareTo(a.stats!.averageRating);
        if (byRating != 0) return byRating;
        return bc.compareTo(ac);
      });
    case 'rating_asc':
      items.sort((a, b) {
        final ac = a.stats?.count ?? 0;
        final bc = b.stats?.count ?? 0;
        if (ac == 0 && bc == 0) return 0;
        if (ac == 0) return 1;
        if (bc == 0) return -1;
        final byRating =
            a.stats!.averageRating.compareTo(b.stats!.averageRating);
        if (byRating != 0) return byRating;
        return ac.compareTo(bc);
      });
    case 'newest':
    default:
      break;
  }
}

final displayedRoutesProvider = FutureProvider<List<RouteListItem>>((ref) async {
  final sort = ref.watch(routeSortProvider);
  final routes = await ref.watch(routesProvider.future);
  if (routes.isEmpty) return [];

  final aggregates = await ref
      .read(routeRatingsRepositoryProvider)
      .fetchAggregatesForRoutes(routes.map((r) => r.id).toList());

  final items = [
    for (final route in routes)
      RouteListItem(route: route, stats: aggregates[route.id]),
  ];
  sortRouteListItems(items, sort);
  return items;
});
