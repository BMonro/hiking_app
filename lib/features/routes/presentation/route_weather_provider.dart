import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/backend_api.dart';
import '../../weather/data/weather_repository.dart';
import '../../weather/domain/weather_model.dart';
import 'routes_provider.dart';

class WaypointWeatherRow {
  final String label;
  final WeatherModel weather;

  const WaypointWeatherRow({
    required this.label,
    required this.weather,
  });
}

class RouteWeatherLoaded {
  final String routeTitle;
  final List<WaypointWeatherRow> points;

  const RouteWeatherLoaded({
    required this.routeTitle,
    required this.points,
  });

  bool get hasPoints => points.isNotEmpty;

  String get tempRangeStr {
    if (points.isEmpty) return '—';
    final temps = points.map((p) => p.weather.temperature).toList();
    final minT = temps.reduce(math.min);
    final maxT = temps.reduce(math.max);
    if ((maxT - minT).abs() < 0.5) {
      return '${minT.round()}°C';
    }
    return '${minT.round()}°C – ${maxT.round()}°C';
  }

  String get windRangeStr {
    if (points.isEmpty) return '—';
    final speeds = points.map((p) => p.weather.windSpeed * 3.6).toList();
    final maxS = speeds.reduce(math.max);
    final minS = speeds.reduce(math.min);
    if ((maxS - minS).abs() < 1) {
      return '${maxS.round()} км/год';
    }
    return '${minS.round()} – ${maxS.round()} км/год';
  }

  String get humidityRangeStr {
    if (points.isEmpty) return '—';
    final hs = points.map((p) => p.weather.humidity.toDouble()).toList();
    final minH = hs.reduce(math.min).round();
    final maxH = hs.reduce(math.max).round();
    if (minH == maxH) return '$minH%';
    return '$minH% – $maxH%';
  }

  String? get warningText {
    if (points.isEmpty) return null;
    final rainPoints =
        points.where((p) => _looksLikeRain(p.weather.description)).length;
    final maxWindMs = points.map((p) => p.weather.windSpeed).reduce(math.max);
    final parts = <String>[];
    if (rainPoints > 0) {
      parts.add(
        rainPoints >= points.length
            ? 'На всьому маршруті можливі опади'
            : 'На частині точок очікуються опади',
      );
    }
    if (maxWindMs >= 10) {
      parts.add('Сильний вітер на окремих ділянках');
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  List<String> get recommendationTexts {
    if (points.isEmpty) return const [];
    final out = <String>[];
    final minT = points.map((p) => p.weather.temperature).reduce(math.min);
    final maxT = points.map((p) => p.weather.temperature).reduce(math.max);
    final maxWindMs = points.map((p) => p.weather.windSpeed).reduce(math.max);
    final anyRain = points.any((p) => _looksLikeRain(p.weather.description));

    if (anyRain) {
      out.add('Візьміть дощовик або водовідштовхувальний одяг.');
    }
    if (maxWindMs >= 10) {
      out.add('Для поривів вітру підійде вітрозахисний шар.');
    }
    if (minT < 5) {
      out.add('На холодних ділянках додайте теплий шар.');
    }
    if (maxT > 26) {
      out.add('У спекотні години беріть більше води та головний убір.');
    }
    if (out.isEmpty) {
      out.add('Перевірте прогноз перед стартом і візьміть запас води.');
    }
    return out;
  }
}

bool _looksLikeRain(String description) {
  final d = description.toLowerCase();
  return d.contains('дощ') ||
      d.contains('злив') ||
      d.contains('гроз') ||
      d.contains('rain') ||
      d.contains('drizzle') ||
      d.contains('thunder') ||
      d.contains('опад');
}

final routeOpenWeatherProvider =
    FutureProvider.family<RouteWeatherLoaded?, String>((ref, routeId) async {
  try {
    final data = await BackendApi().invoke(
      'weather',
      body: {'action': 'route', 'route_id': routeId},
      timeout: const Duration(seconds: 90),
    );

    final pointsRaw = data['points'] as List? ?? [];
    final rows = pointsRaw.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final weatherJson = Map<String, dynamic>.from(m['weather'] as Map);
      return WaypointWeatherRow(
        label: m['label']?.toString() ?? 'Точка',
        weather: WeatherModel.fromJson(weatherJson),
      );
    }).toList();

    return RouteWeatherLoaded(
      routeTitle: data['route_title']?.toString() ?? '',
      points: rows,
    );
  } catch (_) {
    final detail = await ref.watch(routeDetailProvider(routeId).future);
    if (detail == null) return null;

    final repo = ref.read(weatherRepositoryProvider);
    final waypoints = detail.waypoints;

    if (waypoints.isEmpty) {
      return RouteWeatherLoaded(routeTitle: detail.route.title, points: []);
    }

    final rows = await Future.wait(
      waypoints.map((w) async {
        final label =
            (w.name != null && w.name!.isNotEmpty) ? w.name! : w.typeLabelUk;
        final weather = await repo.getWeatherByCoords(
          w.position.latitude,
          w.position.longitude,
        );
        return WaypointWeatherRow(label: label, weather: weather);
      }),
    );

    return RouteWeatherLoaded(routeTitle: detail.route.title, points: rows);
  }
});
