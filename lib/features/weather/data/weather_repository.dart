import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/backend_api.dart';
import '../../../core/config/weather_config.dart';
import '../domain/weather_model.dart';

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return WeatherRepository();
});

class WeatherRepository {
  WeatherRepository({Dio? dio, BackendApi? api})
      : _dio = dio ?? Dio(),
        _api = api ?? BackendApi();

  final Dio _dio;
  final BackendApi _api;

  Future<WeatherModel> getWeatherByCity(String city) async {
    try {
      final data = await _api.invoke(
        'weather',
        body: {'action': 'city', 'city': city},
      );
      return WeatherModel.fromJson(
        Map<String, dynamic>.from(data['current'] as Map),
      );
    } catch (_) {
      return _getWeatherByCityLocal(city);
    }
  }

  Future<({WeatherModel current, List<WeatherForecastDay> forecast})>
      getCurrentAndForecastByCoords(double lat, double lon) async {
    try {
      final data = await _api.invoke(
        'weather',
        body: {'action': 'both', 'lat': lat, 'lon': lon},
      );
      final current = WeatherModel.fromJson(
        Map<String, dynamic>.from(data['current'] as Map),
      );
      final forecast = _parseForecastDays(data['forecast']);
      return (current: current, forecast: forecast);
    } catch (_) {
      final r = await Future.wait([
        getWeatherByCoords(lat, lon),
        get5DayForecastByCoords(lat, lon),
      ]);
      return (
        current: r[0] as WeatherModel,
        forecast: r[1] as List<WeatherForecastDay>,
      );
    }
  }

  Future<WeatherModel> getWeatherByCoords(double lat, double lon) async {
    try {
      final data = await _api.invoke(
        'weather',
        body: {'action': 'current', 'lat': lat, 'lon': lon},
      );
      return WeatherModel.fromJson(
        Map<String, dynamic>.from(data['current'] as Map),
      );
    } catch (_) {
      return _getWeatherByCoordsLocal(lat, lon);
    }
  }

  Future<List<WeatherForecastDay>> get5DayForecastByCoords(
    double lat,
    double lon,
  ) async {
    try {
      final data = await _api.invoke(
        'weather',
        body: {'action': 'forecast', 'lat': lat, 'lon': lon},
      );
      return _parseForecastDays(data['forecast']);
    } catch (_) {
      final items = await _getForecast3hLocal(lat, lon);
      return _buildForecastDaysFromOwm(items);
    }
  }

  List<WeatherForecastDay> _parseForecastDays(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final dateStr = m['date'] as String? ?? '';
      final parts = dateStr.split('-');
      final date = parts.length == 3
          ? DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            )
          : DateTime.now();
      return WeatherForecastDay(
        date: date,
        tempDay: (m['temp_day'] as num).toDouble(),
        tempNight: (m['temp_night'] as num).toDouble(),
        icon: m['icon'] as String? ?? '01d',
      );
    }).toList();
  }

  // --- Локальний fallback ---

  Future<WeatherModel> _getWeatherByCityLocal(String city) async {
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

  Future<WeatherModel> _getWeatherByCoordsLocal(double lat, double lon) async {
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

  Future<List<Map<String, dynamic>>> _getForecast3hLocal(
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

  List<WeatherForecastDay> _buildForecastDaysFromOwm(
    List<Map<String, dynamic>> items,
  ) {
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
        if (hour >= 9 && hour <= 18) {
          dayMax = dayMax == null ? temp : (temp > dayMax ? temp : dayMax);
        }
        if (hour <= 6 || hour >= 21) {
          nightMin =
              nightMin == null ? temp : (temp < nightMin ? temp : nightMin);
        }

        final diff = (hour - 12).abs();
        if (diff < bestNoonDiff) {
          bestNoonDiff = diff;
          noonPick = e;
        }
      }

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
