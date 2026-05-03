import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/osm_nominatim_service.dart';

/// Поле назви точки з підказками з OpenStreetMap (Nominatim).
class OsmRoutePointNameField extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController latController;
  final TextEditingController lonController;
  final TextEditingController altController;
  final VoidCallback onCoordinatesApplied;

  const OsmRoutePointNameField({
    super.key,
    required this.nameController,
    required this.latController,
    required this.lonController,
    required this.altController,
    required this.onCoordinatesApplied,
  });

  @override
  State<OsmRoutePointNameField> createState() => _OsmRoutePointNameFieldState();
}

class _OsmRoutePointNameFieldState extends State<OsmRoutePointNameField> {
  final OsmNominatimService _service = OsmNominatimService();
  final FocusNode _focus = FocusNode();

  Timer? _debounce;
  List<OsmPlaceResult> _suggestions = const [];
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
          setState(() => _suggestions = const []);
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
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _runSearch(raw);
    });
  }

  Future<void> _runSearch(String raw) async {
    final q = raw.trim();
    if (q.length < 3) {
      if (mounted) {
        setState(() {
          _suggestions = const [];
          _loading = false;
        });
      }
      return;
    }

    final gen = ++_requestGen;
    if (mounted) setState(() => _loading = true);

    try {
      final list = await _service.search(q);
      if (!mounted || gen != _requestGen) return;
      setState(() {
        _suggestions = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _requestGen) return;
      setState(() {
        _suggestions = const [];
        _loading = false;
      });
    }
  }

  void _apply(OsmPlaceResult place) {
    widget.nameController.text = place.primaryLabel;
    widget.latController.text = place.lat.toStringAsFixed(5);
    widget.lonController.text = place.lon.toStringAsFixed(5);
    if (place.elevationM != null) {
      widget.altController.text = place.elevationM.toString();
    }
    setState(() => _suggestions = const []);
    widget.onCoordinatesApplied();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.nameController,
          focusNode: _focus,
          decoration: InputDecoration(
            hintText: 'Назва або пошук у OpenStreetMap…',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Icon(Icons.search, color: Colors.grey[600]),
          ),
          onChanged: (value) {
            widget.onCoordinatesApplied();
            _scheduleSearch(value);
          },
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
          '© OSM: Nominatim + пошук вершин (Overpass). Оберіть пункт — підставляться координати.',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }
}
