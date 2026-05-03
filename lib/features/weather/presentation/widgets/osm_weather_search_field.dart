import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../routes/data/osm_nominatim_service.dart';
import '../../domain/place_suggestion.dart';

/// Стиль як у екрана погоди: біле поле, округлення 14.
class _WeatherSearchStyle {
  static const surface = Colors.white;
  static const primary = Color(0xFF2E7D32);
  static const border = Color(0xFFE3E7E2);
}

/// Пошук місця для погоди: debounce + OSM (Nominatim + вершини) + точки з `route_points`.
/// Логіка як у [OsmRoutePointNameField], без Riverpod на кожен символ.
class OsmWeatherSearchField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<PlaceSuggestion> onPick;
  final ValueChanged<String>? onTextChanged;

  const OsmWeatherSearchField({
    super.key,
    required this.controller,
    required this.onPick,
    this.onTextChanged,
  });

  @override
  State<OsmWeatherSearchField> createState() => _OsmWeatherSearchFieldState();
}

class _Hit {
  final String title;
  final String subtitle;
  final IconData icon;
  final PlaceSuggestion place;

  const _Hit({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.place,
  });
}

class _OsmWeatherSearchFieldState extends State<OsmWeatherSearchField> {
  final OsmNominatimService _osm = OsmNominatimService();
  final FocusNode _focus = FocusNode();

  Timer? _debounce;
  List<_Hit> _hits = const [];
  bool _loading = false;
  int _requestGen = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) {
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_focus.hasFocus) {
          setState(() => _hits = const []);
        }
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    super.dispose();
  }

  void _scheduleSearch(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(raw);
    });
  }

  Future<List<_Hit>> _hitsFromCatalog(String q) async {
    final out = <_Hit>[];
    try {
      final data = await Supabase.instance.client
          .from('route_points')
          .select('name, latitude, longitude, point_type')
          .ilike('name', '%$q%')
          .limit(14);

      final list = (data as List).whereType<Map>().toList();
      for (final row in list) {
        final label = (row['name']?.toString() ?? '').trim();
        final lat = (row['latitude'] as num?)?.toDouble();
        final lon = (row['longitude'] as num?)?.toDouble();
        final pt = row['point_type']?.toString() ?? 'viewpoint';
        if (lat == null || lon == null || label.isEmpty) continue;
        out.add(
          _Hit(
            title: label,
            subtitle: _dbPointSubtitle(pt),
            icon: _dbPointIcon(pt),
            place: PlaceSuggestion(
              label: label,
              lat: lat,
              lon: lon,
              type: pt,
            ),
          ),
        );
      }
    } catch (_) {}
    return out;
  }

  Future<List<_Hit>> _hitsFromOsm(String q) async {
    try {
      final osmList = await _osm.search(q);
      return osmList
          .map(
            (r) => _Hit(
              title: r.primaryLabel,
              subtitle: r.displayName,
              icon: r.isPeak ? Icons.terrain : Icons.place_outlined,
              place: PlaceSuggestion(
                label: r.primaryLabel,
                lat: r.lat,
                lon: r.lon,
                type: r.isPeak ? 'peak' : 'place',
              ),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _runSearch(String raw) async {
    final q = raw.trim();
    if (q.length < 3) {
      if (mounted) {
        setState(() {
          _hits = const [];
          _loading = false;
        });
      }
      return;
    }

    final gen = ++_requestGen;
    if (mounted) setState(() => _loading = true);

    final lists = await Future.wait([
      _hitsFromCatalog(q),
      _hitsFromOsm(q),
    ]);

    if (!mounted || gen != _requestGen) return;

    final out = <_Hit>[];
    final seen = <String>{};

    void addHit(_Hit h) {
      final p = h.place;
      if (!p.hasCoords || p.label.isEmpty) return;
      final k =
          '${p.label.toLowerCase()}_${p.lat!.toStringAsFixed(4)}_${p.lon!.toStringAsFixed(4)}';
      if (seen.contains(k)) return;
      seen.add(k);
      out.add(h);
    }

    for (final h in lists[0]) {
      addHit(h);
    }
    for (final h in lists[1]) {
      addHit(h);
    }

    setState(() {
      _hits = out.take(18).toList();
      _loading = false;
    });
  }

  static String _dbPointSubtitle(String pt) {
    return switch (pt) {
      'start' => 'Точка з каталогу · старт',
      'finish' => 'Точка з каталогу · фініш',
      'peak' => 'Точка з каталогу · вершина',
      'viewpoint' => 'Точка з каталогу · огляд',
      'water' => 'Точка з каталогу · вода',
      'shelter' => 'Точка з каталогу · притулок',
      'danger' => 'Точка з каталогу · небезпека',
      _ => 'Точка з каталогу маршрутів',
    };
  }

  static IconData _dbPointIcon(String pt) {
    return switch (pt) {
      'start' => Icons.play_circle_outline,
      'finish' => Icons.flag_circle_outlined,
      'peak' => Icons.terrain,
      'viewpoint' => Icons.visibility_outlined,
      'water' => Icons.water_drop_outlined,
      'shelter' => Icons.home_work_outlined,
      'danger' => Icons.warning_amber_outlined,
      _ => Icons.push_pin_outlined,
    };
  }

  void _apply(_Hit hit) {
    widget.onPick(hit.place);
    widget.controller.text = hit.place.label;
    setState(() => _hits = const []);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: _focus,
          decoration: InputDecoration(
            hintText: 'Назва або пошук у OpenStreetMap…',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: _WeatherSearchStyle.surface,
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Icon(Icons.search, color: Colors.grey[600]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          onChanged: (value) {
            widget.onTextChanged?.call(value);
            _scheduleSearch(value);
          },
          onSubmitted: (value) {
            final v = value.trim();
            if (v.isEmpty) return;
            widget.onPick(
              PlaceSuggestion(label: v, lat: null, lon: null, type: null),
            );
          },
        ),
        if (_hits.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                  color: _WeatherSearchStyle.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _WeatherSearchStyle.border),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _hits.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Colors.grey[300],
                    ),
                    itemBuilder: (context, index) {
                      final h = _hits[index];
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: Icon(
                          h.icon,
                          size: 22,
                          color: _WeatherSearchStyle.primary,
                        ),
                        title: Text(
                          h.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          h.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                        onTap: () => _apply(h),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          '© OSM (Nominatim + вершини) та точки з ваших маршрутів. Мін. 3 символи.',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }
}
