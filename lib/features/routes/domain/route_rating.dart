import 'route_model.dart';

class RouteRatingAggregate {
  final String routeId;
  final double averageRating;
  final int count;

  const RouteRatingAggregate({
    required this.routeId,
    required this.averageRating,
    required this.count,
  });
}

class RouteListItem {
  final RouteModel route;
  final RouteRatingAggregate? stats;

  const RouteListItem({required this.route, this.stats});
}

class RouteReview {
  final String id;
  final String userId;
  final String routeId;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final String authorName;
  final String? authorAvatarUrl;

  const RouteReview({
    required this.id,
    required this.userId,
    required this.routeId,
    required this.rating,
    this.comment,
    required this.createdAt,
    required this.authorName,
    this.authorAvatarUrl,
  });

  factory RouteReview.fromRow(
    Map<String, dynamic> json, {
    String authorName = 'Користувач',
    String? authorAvatarUrl,
  }) {
    return RouteReview(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      routeId: json['route_id']?.toString() ?? '',
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: (json['comment'] as String?)?.trim(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
    );
  }
}

class RouteReviewsSummary {
  final List<RouteReview> reviews;
  final RouteReview? myReview;

  const RouteReviewsSummary({
    required this.reviews,
    this.myReview,
  });

  int get count => reviews.length;

  double? get averageRating {
    if (reviews.isEmpty) return null;
    final sum = reviews.fold<int>(0, (s, r) => s + r.rating);
    return sum / reviews.length;
  }

  String get averageLabel {
    final avg = averageRating;
    if (avg == null) return '—';
    return avg.toStringAsFixed(1);
  }

  static String reviewsCountLabel(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 14) return '$count відгуків';
    if (mod10 == 1) return '$count відгук';
    if (mod10 >= 2 && mod10 <= 4) return '$count відгуки';
    return '$count відгуків';
  }
}
