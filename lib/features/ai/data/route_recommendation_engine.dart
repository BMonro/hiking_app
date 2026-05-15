import '../../routes/domain/route_model.dart';

/// Резервний підбір маршрутів без ШІ — за полями профілю.
class RouteRecommendationEngine {
  List<RouteRecommendationCandidate> rank({
    required Map<String, dynamic>? profile,
    required List<RouteModel> routes,
    int limit = 5,
  }) {
    if (routes.isEmpty) return [];

    final prefDiff = profile?['preferred_difficulty']?.toString();
    final fitness = profile?['fitness_level']?.toString() ?? 'beginner';
    final prefDuration =
        (profile?['preferred_duration_h'] as num?)?.toDouble();
    final experience = (profile?['experience_count'] as num?)?.toInt() ?? 0;

    final targetDiff = prefDiff ?? _difficultyFromFitness(fitness);

    final scored = <({RouteModel route, double score, String reason})>[];
    for (final route in routes) {
      var score = 0.0;
      final parts = <String>[];

      final diffScore = _difficultyScore(targetDiff, route.difficulty);
      score += diffScore * 40;
      if (diffScore > 0.7) {
        parts.add('відповідає вашій складності');
      }

      if (prefDuration != null && prefDuration > 0 && route.durationH > 0) {
        final ratio = route.durationH / prefDuration;
        if (ratio <= 1.15) {
          score += 25;
          parts.add('комфортна тривалість');
        } else if (ratio <= 1.4) {
          score += 10;
        } else {
          score -= 15;
        }
      }

      if (experience < 3 && route.difficulty == 'easy') {
        score += 15;
        parts.add('підходить для набору досвіду');
      } else if (experience >= 10 && route.difficulty == 'hard') {
        score += 10;
        parts.add('цікавий виклик для досвідченого');
      }

      if (route.ascentM > 0 && route.ascentM <= 600 && fitness == 'beginner') {
        score += 8;
      }

      final reason = parts.isEmpty
          ? 'Збалансований варіант для вашого профілю'
          : parts.join(', ');
      scored.add((route: route, score: score, reason: _capitalize(reason)));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored
        .take(limit)
        .map(
          (e) => RouteRecommendationCandidate(
            route: e.route,
            reason: e.reason,
          ),
        )
        .toList();
  }

  String _difficultyFromFitness(String fitness) {
    return switch (fitness) {
      'advanced' => 'hard',
      'intermediate' => 'medium',
      _ => 'easy',
    };
  }

  double _difficultyScore(String target, String actual) {
    const order = ['easy', 'medium', 'hard'];
    final ti = order.indexOf(target);
    final ai = order.indexOf(actual);
    if (ti < 0 || ai < 0) return 0.5;
    final diff = (ai - ti).abs();
    return switch (diff) {
      0 => 1.0,
      1 => 0.65,
      _ => 0.25,
    };
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }
}

class RouteRecommendationCandidate {
  final RouteModel route;
  final String reason;

  const RouteRecommendationCandidate({
    required this.route,
    required this.reason,
  });
}
