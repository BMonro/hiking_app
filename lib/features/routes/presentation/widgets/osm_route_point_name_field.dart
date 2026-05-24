import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/validation/form_validators.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/osm_nominatim_service.dart';

class OsmRoutePointNameField extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController latController;
  final TextEditingController lonController;
  final TextEditingController altController;
  final VoidCallback onCoordinatesApplied;
  final bool nameRequired;

  const OsmRoutePointNameField({
    super.key,
    required this.nameController,
    required this.latController,
    required this.lonController,
    required this.altController,
    required this.onCoordinatesApplied,
    this.nameRequired = false,
  });

  @override
  State<OsmRoutePointNameField> createState() => _OsmRoutePointNameFieldState();
}

class _OsmRoutePointNameFieldState extends State<OsmRoutePointNameField> {
  final OsmNominatimService _service = OsmNominatimService();
  final FocusNode _focus = FocusNode();

  Timer? _debounce;
  CancelToken? _cancelToken;
  List<OsmPlaceResult> _suggestions = const [];
  bool _loading = false;
  bool _loadingPeaks = false;
  bool _hideSuggestionsUntilEdit = false;
  int _requestGen = 0;

  static final Map<String, List<OsmPlaceResult>> _localCache = {};
  static const _localCacheMax = 40;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      _hideSuggestionsUntilEdit = false;
    } else {
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_focus.hasFocus) {
          setState(() => _suggestions = const []);
        }
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancelToken?.cancel('dispose');
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    super.dispose();
  }

  void _scheduleSearch(String raw) {
    if (_hideSuggestionsUntilEdit) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _runSearch(raw);
    });
  }

  void _dismissSuggestions() {
    _debounce?.cancel();
    _cancelToken?.cancel('pick');
    _requestGen++;
    _hideSuggestionsUntilEdit = true;
    if (mounted) {
      setState(() {
        _suggestions = const [];
        _loading = false;
        _loadingPeaks = false;
      });
    }
    _focus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  static void _cacheSuggestions(String key, List<OsmPlaceResult> list) {
    if (list.isEmpty) return;
    if (_localCache.length >= _localCacheMax) {
      _localCache.remove(_localCache.keys.first);
    }
    _localCache[key] = list;
  }

  Future<List<OsmPlaceResult>> _fromCatalog(String q) async {
    final out = <OsmPlaceResult>[];
    try {
      final data = await Supabase.instance.client
          .from('route_points')
          .select('name, latitude, longitude, point_type, altitude_m')
          .ilike('name', '%$q%')
          .limit(8);

      for (final row in (data as List).whereType<Map>()) {
        final label = (row['name']?.toString() ?? '').trim();
        final lat = (row['latitude'] as num?)?.toDouble();
        final lon = (row['longitude'] as num?)?.toDouble();
        final pt = row['point_type']?.toString() ?? 'viewpoint';
        final alt = row['altitude_m'] as int?;
        if (lat == null || lon == null || label.isEmpty) continue;
        out.add(
          OsmPlaceResult(
            displayName: 'Точка з каталогу · $pt',
            primaryLabel: label,
            lat: lat,
            lon: lon,
            elevationM: alt,
            isPeak: pt == 'peak',
          ),
        );
      }
    } catch (_) {}
    return out;
  }

  Future<void> _runSearch(String raw) async {
    final q = raw.trim();
    if (q.length < 3) {
      _cancelToken?.cancel('short_query');
      if (mounted) {
        setState(() {
          _suggestions = const [];
          _loading = false;
          _loadingPeaks = false;
        });
      }
      return;
    }

    final cacheKey = q.toLowerCase();
    final cached = _localCache[cacheKey];
    if (cached != null) {
      if (!_hideSuggestionsUntilEdit && mounted) {
        setState(() {
          _suggestions = cached;
          _loading = false;
          _loadingPeaks = false;
        });
      }
      return;
    }

    final gen = ++_requestGen;
    _cancelToken?.cancel('new_search');
    _cancelToken = CancelToken();
    final token = _cancelToken!;

    if (mounted) {
      setState(() {
        _loading = true;
        _loadingPeaks = false;
      });
    }

    var catalog = <OsmPlaceResult>[];
    var places = <OsmPlaceResult>[];

    try {
      await Future.wait([
        _fromCatalog(q)
            .timeout(const Duration(seconds: 2), onTimeout: () => const [])
            .then((v) => catalog = v)
            .catchError((_) => const <OsmPlaceResult>[]),
        _service
            .searchForRoutePlaces(q, cancelToken: token)
            .timeout(const Duration(seconds: 8), onTimeout: () => const [])
            .then((v) => places = v)
            .catchError((_) => const <OsmPlaceResult>[]),
      ]).timeout(const Duration(seconds: 8));
    } on TimeoutException {

    }

    if (!mounted || gen != _requestGen || _hideSuggestionsUntilEdit) return;

    var merged = _service.mergeRouteSuggestions(catalog, places, const []);
    setState(() {
      _suggestions = merged;
      _loading = false;
      _loadingPeaks = true;
    });

    try {
      final peaks = await _service
          .searchForRoutePeaks(q, cancelToken: token)
          .timeout(const Duration(seconds: 12), onTimeout: () => const []);
      if (!mounted || gen != _requestGen || _hideSuggestionsUntilEdit) return;
      merged = _service.mergeRouteSuggestions(catalog, places, peaks);
      _cacheSuggestions(cacheKey, merged);
      setState(() {
        _suggestions = merged;
        _loadingPeaks = false;
      });
    } catch (_) {
      if (!mounted || gen != _requestGen) return;
      _cacheSuggestions(cacheKey, merged);
      setState(() => _loadingPeaks = false);
    }
  }

  void _apply(OsmPlaceResult place) {
    _dismissSuggestions();
    widget.nameController.text = place.primaryLabel;
    widget.latController.text = place.lat.toStringAsFixed(5);
    widget.lonController.text = place.lon.toStringAsFixed(5);
    if (place.elevationM != null) {
      widget.altController.text = place.elevationM.toString();
    }
    widget.onCoordinatesApplied();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.nameController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.nameController,
          focusNode: _focus,
          validator: (v) =>
              FormValidators.pointName(v, requiredField: widget.nameRequired),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
            hintText: 'Назва або пошук у OpenStreetMap…',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            suffixIcon: _loading || _loadingPeaks
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _loadingPeaks && !_loading
                            ? Colors.grey
                            : null,
                      ),
                    ),
                  )
                : Icon(Icons.search, color: Colors.grey[600]),
          ),
          onChanged: (value) {
            widget.onCoordinatesApplied();
            _scheduleSearch(value);
          },
        ),
        if (!_loading &&
            !_loadingPeaks &&
            q.length >= 3 &&
            _suggestions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Нічого не знайдено. Спробуйте повну назву.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
        if (_suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey[300]),
                  itemBuilder: (context, index) {
                    final s = _suggestions[index];
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: Icon(
                        s.isPeak ? Icons.terrain : Icons.place_outlined,
                        size: 22,
                        color: Colors.green[800],
                      ),
                      title: Text(
                        s.primaryLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        s.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                      onTap: () => _apply(s),
                    );
                  },
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Каталог + OpenStreetMap. Спочатку міста, потім вершини.',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }
}
