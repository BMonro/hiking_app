import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/routes_repository.dart';
import '../domain/route_detail.dart';
import '../domain/route_model.dart';

final routesRepositoryProvider = Provider((ref) => RoutesRepository());

final searchQueryProvider = StateProvider<String>((ref) => '');
final difficultyFilterProvider = StateProvider<String>((ref) => 'all');
/// `all` | `circular` | `linear` | `radial` | `combined`
final routeTypeFilterProvider = StateProvider<String>((ref) => 'all');
final durationMaxFilterProvider = StateProvider<double?>((ref) => null);
final ascentMaxFilterProvider = StateProvider<int?>((ref) => null);

final routesProvider = FutureProvider<List<RouteModel>>((ref) async {
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

final routeDetailProvider =
    FutureProvider.family<RouteDetail?, String>((ref, routeId) async {
  final repo = ref.watch(routesRepositoryProvider);
  return repo.getRouteDetail(routeId);
});
