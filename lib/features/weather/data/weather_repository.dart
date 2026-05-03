import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/weather_model.dart';
import '../../../core/config/weather_config.dart';

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return WeatherRepository();
});

class WeatherRepository {
  final _dio = Dio();

  Future<WeatherModel> getWeatherByCity(String city) async {
    final response = await _dio.get(
      '${WeatherConfig.baseUrl}/weather',
      queryParameters: {
        'q': city,
        'appid': WeatherConfig.apiKey,
        'lang': 'uk',
        'units': 'metric',
      },
    );
    return WeatherModel.fromJson(response.data);
  }

  /// Два незалежні запити до OpenWeather паралельно (швидше за послідовний виклик).
  Future<({WeatherModel current, List<WeatherForecastDay> forecast})>
      getCurrentAndForecastByCoords(double lat, double lon) async {
    final r = await Future.wait([
      getWeatherByCoords(lat, lon),
      get5DayForecastByCoords(lat, lon),
    ]);
    return (
      current: r[0] as WeatherModel,
      forecast: r[1] as List<WeatherForecastDay>,
    );
  }

  Future<WeatherModel> getWeatherByCoords(double lat, double lon) async {
    final response = await _dio.get(
      '${WeatherConfig.baseUrl}/weather',
      queryParameters: {
        'lat': lat,
        'lon': lon,
        'appid': WeatherConfig.apiKey,
        'lang': 'uk',
        'units': 'metric',
      },
    );
    return WeatherModel.fromJson(response.data);
  }

  Future<List<Map<String, dynamic>>> getForecast3hByCoords(
    double lat,
    double lon,
  ) async {
    final response = await _dio.get(
      '${WeatherConfig.baseUrl}/forecast',
      queryParameters: {
        'lat': lat,
        'lon': lon,
        'appid': WeatherConfig.apiKey,
        'lang': 'uk',
        'units': 'metric',
        'cnt': 40,
      },
    );
    return (response.data['list'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<WeatherForecastDay>> get5DayForecastByCoords(
    double lat,
    double lon,
  ) async {
    final items = await getForecast3hByCoords(lat, lon);

    // Group by local date and compute day/night temps.
    final Map<DateTime, List<Map<String, dynamic>>> byDay = {};
    for (final item in items) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
        (item['dt'] as num).toInt() * 1000,
        isUtc: true,
      ).toLocal();
      final dayKey = DateTime(dt.year, dt.month, dt.day);
      (byDay[dayKey] ??= []).add(item);
    }

    final keys = byDay.keys.toList()..sort();
    final result = <WeatherForecastDay>[];

    for (final day in keys) {
      final entries = byDay[day]!;
      if (entries.isEmpty) continue;

      double? dayMax;
      double? nightMin;

      // pick icon closest to 12:00
      Map<String, dynamic>? noonPick;
      int bestNoonDiff = 999999;

      for (final e in entries) {
        final temp = (e['main']?['temp'] as num?)?.toDouble();
        if (temp == null) continue;

        final dt = DateTime.fromMillisecondsSinceEpoch(
          (e['dt'] as num).toInt() * 1000,
          isUtc: true,
        ).toLocal();

        final hour = dt.hour;
        final isDay = hour >= 9 && hour <= 18;
        final isNight = hour <= 6 || hour >= 21;

        if (isDay) {
          dayMax = dayMax == null ? temp : (temp > dayMax ? temp : dayMax);
        }
        if (isNight) {
          nightMin =
              nightMin == null ? temp : (temp < nightMin ? temp : nightMin);
        }

        final diff = (hour - 12).abs();
        if (diff < bestNoonDiff) {
          bestNoonDiff = diff;
          noonPick = e;
        }
      }

      // Fallbacks if a day has only partial hours
      if (dayMax == null || nightMin == null) {
        final temps = entries
            .map((e) => (e['main']?['temp'] as num?)?.toDouble())
            .whereType<double>()
            .toList();
        if (temps.isNotEmpty) {
          dayMax ??= temps.reduce((a, b) => a > b ? a : b);
          nightMin ??= temps.reduce((a, b) => a < b ? a : b);
        }
      }

      final icon = (noonPick?['weather']?[0]?['icon'] as String?) ?? '01d';
      if (dayMax == null || nightMin == null) continue;

      result.add(
        WeatherForecastDay(
          date: day,
          tempDay: dayMax,
          tempNight: nightMin,
          icon: icon,
        ),
      );

      if (result.length >= 5) break;
    }

    return result;
  }
}
