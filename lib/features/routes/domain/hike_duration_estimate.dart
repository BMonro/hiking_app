import 'dart:math' as math;

class HikeSegmentInput {
  const HikeSegmentInput({
    required this.distanceM,
    this.deltaAltM,
  });

  final double distanceM;

  final int? deltaAltM;
}

class HikeDurationResult {
  const HikeDurationResult({
    required this.distanceKm,
    required this.ascentM,
    required this.descentM,
    required this.durationH,
    this.durationHint,
  });

  final double distanceKm;
  final int ascentM;
  final int descentM;
  final double durationH;
  final String? durationHint;
}

class HikeDurationEstimate {
  HikeDurationEstimate._();

  static const double flatSpeedKmh = 4.0;
  static const double ascentMinPer100m = 10.0;
  static const double descentMinPer100mGentle = 4.0;
  static const double descentMinPer100mSteep = 9.0;
  static const double steepGradePercent = 18.0;
  static const double fatigueEffortThreshold = 8.0;
  static const double maxFatigueMultiplier = 1.35;

  static HikeDurationResult fromSegments(List<HikeSegmentInput> segments) {
    var totalMeters = 0.0;
    var ascent = 0;
    var descent = 0;
    var totalHours = 0.0;
    var cumulativeKm = 0.0;
    var cumulativeAscent = 0.0;
    var hadAltitude = false;
    var hadSteepDescent = false;
    var fatigueApplied = false;

    for (final seg in segments) {
      final distKm = seg.distanceM / 1000.0;
      if (distKm <= 0 && (seg.deltaAltM ?? 0) == 0) continue;

      totalMeters += seg.distanceM;
      final delta = seg.deltaAltM;
      if (delta != null) {
        hadAltitude = true;
        if (delta > 0) ascent += delta;
        if (delta < 0) descent += -delta;
      }

      final fatigue = _fatigueMultiplier(cumulativeKm, cumulativeAscent);
      if (fatigue > 1.01) fatigueApplied = true;

      final segHours = _segmentHours(distKm, delta);
      if (delta != null &&
          delta < 0 &&
          distKm > 0.001 &&
          (-delta / (distKm * 1000)) * 100 >= steepGradePercent) {
        hadSteepDescent = true;
      }

      totalHours += segHours * fatigue;
      cumulativeKm += distKm;
      if (delta != null && delta > 0) cumulativeAscent += delta;
    }

    final km = totalMeters / 1000.0;
    if (km == 0) {
      return const HikeDurationResult(
        distanceKm: 0,
        ascentM: 0,
        descentM: 0,
        durationH: 0,
      );
    }

    if (!hadAltitude) {
      totalHours = _distanceOnlyWithFatigue(km);
    }

    final hints = <String>[];
    if (hadAltitude && descent > 0) {
      hints.add('враховано спуск $descent м');
    }
    if (fatigueApplied) {
      hints.add('додано час на втомливість на довгих ділянках');
    }
    if (hadSteepDescent) {
      hints.add('крутий спуск уповільнює темп');
    }

    return HikeDurationResult(
      distanceKm: double.parse(km.toStringAsFixed(2)),
      ascentM: ascent,
      descentM: descent,
      durationH: double.parse(totalHours.toStringAsFixed(1)),
      durationHint: hints.isEmpty ? null : '${hints.join('; ')}.',
    );
  }

  static double _segmentHours(double distKm, int? deltaAltM) {
    if (distKm <= 0) {
      if (deltaAltM == null || deltaAltM == 0) return 0;
      final climb = deltaAltM > 0 ? deltaAltM : -deltaAltM;
      final minPer100 = deltaAltM > 0 ? ascentMinPer100m : descentMinPer100mSteep;
      return (climb / 100.0) * (minPer100 / 60.0);
    }

    final flatH = distKm / flatSpeedKmh;
    final delta = deltaAltM ?? 0;

    if (delta > 0) {
      final ascentH = (delta / 100.0) * (ascentMinPer100m / 60.0);
      final grade = (delta / (distKm * 1000)) * 100;
      final steepFactor = grade > 25
          ? 1.18
          : grade > 15
              ? 1.10
              : 1.0;
      return (flatH + ascentH) * steepFactor;
    }

    if (delta < 0) {
      final loss = -delta;
      final grade = (loss / (distKm * 1000)) * 100;
      final minPer100 = grade >= steepGradePercent
          ? descentMinPer100mSteep
          : descentMinPer100mGentle;
      final descentH = (loss / 100.0) * (minPer100 / 60.0);
      final downhillFlatH = distKm / 3.3;
      return math.max(flatH, downhillFlatH) + descentH;
    }

    return flatH;
  }

  static double _fatigueMultiplier(double cumulativeKm, double cumulativeAscentM) {
    final effort = cumulativeKm + cumulativeAscentM / 400.0;
    if (effort <= fatigueEffortThreshold) return 1.0;
    final excess = effort - fatigueEffortThreshold;
    return (1.0 + 0.028 * excess).clamp(1.0, maxFatigueMultiplier);
  }

  static double _distanceOnlyWithFatigue(double km) {
    var hours = 0.0;
    var walked = 0.0;
    const stepKm = 0.5;
    while (walked < km) {
      final chunk = math.min(stepKm, km - walked);
      hours += (chunk / flatSpeedKmh) *
          _fatigueMultiplier(walked, 0);
      walked += chunk;
    }
    return hours;
  }
}
