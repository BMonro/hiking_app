
class HikeQualification {
  const HikeQualification._();

  static const double minDistanceKm = 0.2;

  static const int minDurationMinutes = 5;

  static const double minDistanceM = minDistanceKm * 1000;

  static double _hoursFromDuration(Duration d) => d.inSeconds / 3600.0;

  static bool qualifies({
    required double distanceKm,
    required double durationHours,
    required bool reachedFinish,
  }) {
    if (distanceKm >= minDistanceKm &&
        durationHours >= minDurationMinutes / 60.0) {
      return true;
    }

    if (reachedFinish &&
        distanceKm >= 0.15 &&
        durationHours >= 3 / 60.0) {
      return true;
    }

    return false;
  }

  static bool qualifiesFromMeters({
    required double traveledM,
    required Duration duration,
    required bool reachedFinish,
  }) {
    return qualifies(
      distanceKm: traveledM / 1000,
      durationHours: _hoursFromDuration(duration),
      reachedFinish: reachedFinish,
    );
  }

  static String get requirementHint =>
      'мінімум ${(minDistanceKm * 1000).round()} м і $minDurationMinutes хв руху';
}
