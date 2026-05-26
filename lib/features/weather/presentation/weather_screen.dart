import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/network/network_status_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/offline_only_message.dart';
import '../data/weather_repository.dart';
import '../domain/place_suggestion.dart';
import '../domain/weather_model.dart';
import 'widgets/osm_weather_search_field.dart';

class _WeatherColors {
  static const background = Color(0xFFF5F6F4);
  static const surface = Colors.white;
  static const primary = Color(0xFF2E7D32);
  static const primary2 = Color(0xFF66BB6A);
  static const textMain = Color(0xFF1E2A1E);

  static const warningBg = Color(0xFFFFECE8);
  static const warningBorder = Color(0xFFF6B6A8);
  static const warningText = Color(0xFF7A3F35);
}

final _weatherSelectedPlaceProvider =
    StateProvider<PlaceSuggestion?>((ref) => null);

final weatherBundleProvider =
    FutureProvider.family<_WeatherBundle, PlaceSuggestion>((ref, place) async {
  final repo = ref.read(weatherRepositoryProvider);

  if (place.hasCoords) {
    final bundle = await repo.getCurrentAndForecastByCoords(
      place.lat!,
      place.lon!,
    );
    return _WeatherBundle(
      current: bundle.current,
      forecast: bundle.forecast,
      place: place,
    );
  }

  final current = await repo.getWeatherByCity(place.label);
  final forecast = await repo.get5DayForecastByCoords(current.lat, current.lon);
  return _WeatherBundle(current: current, forecast: forecast, place: place);
});

class _WeatherBundle {
  final WeatherModel current;
  final List<WeatherForecastDay> forecast;
  final PlaceSuggestion place;

  const _WeatherBundle({
    required this.current,
    required this.forecast,
    required this.place,
  });
}

class WeatherScreen extends ConsumerStatefulWidget {
  const WeatherScreen({super.key});

  @override
  ConsumerState<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends ConsumerState<WeatherScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(_weatherSelectedPlaceProvider);
    final hasNetwork = ref.watch(hasNetworkProvider).value ?? true;

    if (!hasNetwork) {
      return Scaffold(
        backgroundColor: _WeatherColors.background,
        appBar: AppBar(
          backgroundColor: AppTheme.toolbarBackground,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'Погода',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          centerTitle: true,
        ),
        body: const OfflineOnlyMessage(
          icon: Icons.wb_cloudy_outlined,
          title: 'Погода недоступна офлайн',
          subtitle:
              'Прогноз потребує інтернету. Підключіть Wi‑Fi або мобільні дані.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: _WeatherColors.background,
      appBar: AppBar(
        backgroundColor: AppTheme.toolbarBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Погода',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            OsmWeatherSearchField(
              controller: _searchController,
              onTextChanged: (value) {
                if (selected != null && value.trim() != selected.label) {
                  ref.read(_weatherSelectedPlaceProvider.notifier).state = null;
                }
              },
              onPick: (place) {
                ref.read(_weatherSelectedPlaceProvider.notifier).state = place;
                _searchController.text = place.label;
                FocusScope.of(context).unfocus();
              },
            ),
            const SizedBox(height: 14),
            if (selected == null)
              const Expanded(
                child: Center(
                  child: Text(
                    'Введіть назву (мін. 3 символи): вершина, населений пункт або точка з каталогу — підказки з OpenStreetMap і ваших маршрутів.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final bundleAsync =
                        ref.watch(weatherBundleProvider(selected));
                    return bundleAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline,
                                  size: 48, color: Colors.red[300]),
                              const SizedBox(height: 14),
                              Text(
                                e is DioException
                                    ? 'Не вдалося завантажити погоду.\nСпробуйте іншу назву.'
                                    : 'Помилка: $e',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                            ],
                          ),
                        ),
                      ),
                      data: (bundle) => _WeatherLayout(bundle: bundle),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeatherLayout extends StatelessWidget {
  final _WeatherBundle bundle;

  const _WeatherLayout({required this.bundle});

  @override
  Widget build(BuildContext context) {
    final w = bundle.current;
    final kmh = (w.windSpeed * 3.6).round();
    final visibilityKm = w.visibilityMeters == null
        ? null
        : (w.visibilityMeters! / 1000).round();
    final pressure = w.pressure;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_WeatherColors.primary, _WeatherColors.primary2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${bundle.place.label} - зараз',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${w.temperature.round()}°',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _capitalize(w.description),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Відчувається як ${w.feelsLikeStr}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Image.network(
                        w.iconUrl,
                        width: 42,
                        height: 42,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.wb_cloudy_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _MiniMetric(label: 'Вітер', value: '$kmh км/\nгод'),
                    _MiniMetric(label: 'Вологість', value: '${w.humidity}%'),
                    _MiniMetric(
                      label: 'Видимість',
                      value: visibilityKm == null ? '—' : '${visibilityKm}км',
                    ),
                    _MiniMetric(
                      label: 'Тиск',
                      value: pressure == null ? '—' : '$pressure\nгПа',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Прогноз на 5 днів',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: _WeatherColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE3E7E2)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < bundle.forecast.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: Color(0xFFE3E7E2)),
                  _ForecastRow(
                    day: _dayLabel(bundle.forecast[i].date, i),
                    dayTemp: bundle.forecast[i].dayTempStr,
                    nightTemp: bundle.forecast[i].nightTempStr,
                    iconUrl: bundle.forecast[i].iconUrl,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  static String _capitalize(String value) {
    final v = value.trim();
    if (v.isEmpty) return v;
    return v[0].toUpperCase() + v.substring(1);
  }

  static String _dayLabel(DateTime date, int index) {
    if (index == 0) return 'Сьогодні';
    if (index == 1) return 'Завтра';
    const months = [
      '',
      'січ',
      'лют',
      'бер',
      'квіт',
      'трав',
      'черв',
      'лип',
      'серп',
      'вер',
      'жовт',
      'лист',
      'груд',
    ];
    const weekdays = [
      '',
      'Пн',
      'Вт',
      'Ср',
      'Чт',
      'Пт',
      'Сб',
      'Нд',
    ];
    return '${weekdays[date.weekday]}, ${date.day} ${months[date.month]}';
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;

  const _MiniMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ForecastRow extends StatelessWidget {
  final String day;
  final String dayTemp;
  final String nightTemp;
  final String iconUrl;

  const _ForecastRow({
    required this.day,
    required this.dayTemp,
    required this.nightTemp,
    required this.iconUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              day,
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
          ),
          Image.network(
            iconUrl,
            width: 26,
            height: 26,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.cloud_outlined, size: 22, color: Colors.grey[400]),
          ),
          const SizedBox(width: 10),
          Text(
            '$dayTemp / $nightTemp',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  final String text;

  const _WarningBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final parts = text.split('\n');
    final title = parts.isNotEmpty ? parts.first : 'Попередження';
    final body = parts.length >= 2 ? parts.sublist(1).join('\n') : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _WeatherColors.warningBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _WeatherColors.warningBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _WeatherColors.warningText,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: _WeatherColors.warningText,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
