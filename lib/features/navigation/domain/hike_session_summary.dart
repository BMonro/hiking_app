
class HikeSessionSummary {
  const HikeSessionSummary({
    this.routeId,
    required this.title,
    required this.distanceKm,
    required this.durationHours,
    this.suggestedAscentM,
    required this.reachedFinish,
  });

  final String? routeId;
  final String title;
  final double distanceKm;
  final double durationHours;
  final int? suggestedAscentM;
  final bool reachedFinish;
}
