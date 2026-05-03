import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'route_weather_provider.dart';

class RouteWeatherScreen extends ConsumerStatefulWidget {
  final String routeId;

  const RouteWeatherScreen({
    super.key,
    required this.routeId,
  });

  @override
  ConsumerState<RouteWeatherScreen> createState() => _RouteWeatherScreenState();
}

class _RouteWeatherScreenState extends ConsumerState<RouteWeatherScreen> {
  @override
  Widget build(BuildContext context) {
    final asyncWeather = ref.watch(routeOpenWeatherProvider(widget.routeId));

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F5F2),
        elevation: 0,
        title: const Text(
          'Погода на маршруті',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: asyncWeather.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Не вдалося завантажити погоду: $e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (data) {
          if (data == null) {
            return const Center(child: Text('Маршрут не знайдено'));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.routeTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Поточна погода (OpenWeather) для координат кожної точки маршруту.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                if (!data.hasPoints)
                  Text(
                    'Для цього маршруту ще немає точок у базі.',
                    style: TextStyle(color: Colors.grey[700]),
                  )
                else
                  ...data.points.map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _WaypointWeatherCard(row: row),
                    ),
                  ),
                if (data.hasPoints) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF2196F3).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Зведення по маршруту',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _WeatherInfo(
                          icon: Icons.thermostat,
                          label: 'Температура',
                          value: data.tempRangeStr,
                        ),
                        const SizedBox(height: 8),
                        _WeatherInfo(
                          icon: Icons.air,
                          label: 'Вітер',
                          value: data.windRangeStr,
                        ),
                        const SizedBox(height: 8),
                        _WeatherInfo(
                          icon: Icons.opacity,
                          label: 'Вологість',
                          value: data.humidityRangeStr,
                        ),
                        if (data.warningText != null) ...[
                          const SizedBox(height: 8),
                          _WeatherInfo(
                            icon: Icons.warning_amber,
                            label: 'Попередження',
                            value: data.warningText!,
                            color: Colors.orange.shade800,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Рекомендації',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...data.recommendationTexts.map(
                          (text) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _RecommendationItem(
                              icon: Icons.checkroom,
                              text: text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WaypointWeatherCard extends StatelessWidget {
  final WaypointWeatherRow row;

  const _WaypointWeatherCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final w = row.weather;
    final kmh = (w.windSpeed * 3.6).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  w.iconUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.cloud,
                    size: 36,
                    color: Color(0xFF2196F3),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      w.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                w.temperatureStr,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _SmallWeatherInfo(
                icon: Icons.air,
                label: 'Вітер',
                value: '$kmh км/год',
              ),
              const SizedBox(width: 16),
              _SmallWeatherInfo(
                icon: Icons.opacity,
                label: 'Вологість',
                value: '${w.humidity}%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallWeatherInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SmallWeatherInfo({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeatherInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _WeatherInfo({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color ?? Colors.grey[600], size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecommendationItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _RecommendationItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF4CAF50)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
      ],
    );
  }
}
