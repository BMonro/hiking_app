import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profile/data/public_profile_repository.dart';
import '../domain/route_rating.dart';

class RouteRatingsRepository {
  RouteRatingsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<RouteReviewsSummary> fetchForRoute(String routeId) async {
    final rows = await _client
        .from('route_ratings')
        .select('id, user_id, route_id, rating, comment, created_at')
        .eq('route_id', routeId)
        .order('created_at', ascending: false);

    final list = List<Map<String, dynamic>>.from(rows);
    if (list.isEmpty) {
      return const RouteReviewsSummary(reviews: []);
    }

    final userIds =
        list.map((r) => r['user_id']?.toString()).whereType<String>().toSet();
    final profiles = await PublicProfileRepository(client: _client)
        .fetchByIds(userIds);

    final reviews = list.map((row) {
      final uid = row['user_id']?.toString() ?? '';
      final profile = profiles[uid];
      return RouteReview.fromRow(
        row,
        authorName: profile?.displayName ?? 'Користувач',
        authorAvatarUrl: profile?.avatarUrl,
      );
    }).toList();

    final myId = _client.auth.currentUser?.id;
    RouteReview? mine;
    if (myId != null) {
      for (final r in reviews) {
        if (r.userId == myId) {
          mine = r;
          break;
        }
      }
    }

    return RouteReviewsSummary(reviews: reviews, myReview: mine);
  }

  Future<Map<String, RouteRatingAggregate>> fetchAggregatesForRoutes(
    List<String> routeIds,
  ) async {
    final ids = routeIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};

    final rows = await _client
        .from('route_ratings')
        .select('route_id, rating')
        .inFilter('route_id', ids);

    final sums = <String, int>{};
    final counts = <String, int>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final routeId = row['route_id']?.toString();
      final rating = (row['rating'] as num?)?.toInt();
      if (routeId == null || routeId.isEmpty || rating == null) continue;
      sums[routeId] = (sums[routeId] ?? 0) + rating;
      counts[routeId] = (counts[routeId] ?? 0) + 1;
    }

    final out = <String, RouteRatingAggregate>{};
    for (final entry in counts.entries) {
      final routeId = entry.key;
      final count = entry.value;
      final sum = sums[routeId] ?? 0;
      out[routeId] = RouteRatingAggregate(
        routeId: routeId,
        averageRating: sum / count,
        count: count,
      );
    }
    return out;
  }

  Future<void> submitReview({
    required String routeId,
    required int rating,
    String? comment,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Потрібна авторизація');
    }
    if (rating < 1 || rating > 5) {
      throw ArgumentError('rating must be 1..5');
    }

    final trimmedComment = comment?.trim();
    final payload = <String, dynamic>{
      'user_id': uid,
      'route_id': routeId,
      'rating': rating,
      'comment': (trimmedComment == null || trimmedComment.isEmpty)
          ? null
          : trimmedComment,
    };

    final existing = await _client
        .from('route_ratings')
        .select('id')
        .eq('route_id', routeId)
        .eq('user_id', uid)
        .maybeSingle();

    if (existing != null) {
      await _client
          .from('route_ratings')
          .update({
            'rating': rating,
            'comment': payload['comment'],
          })
          .eq('id', existing['id']);
    } else {
      await _client.from('route_ratings').insert(payload);
    }
  }
}
