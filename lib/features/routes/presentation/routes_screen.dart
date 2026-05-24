import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import '../data/elevation_lookup_service.dart';
import '../data/route_variants_api.dart';
import '../data/save_route_api.dart';
import '../domain/route_variant.dart';
import 'routes_provider.dart';
import '../domain/hike_duration_estimate.dart';
import '../domain/route_detail.dart';
import '../domain/route_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/validation/form_validators.dart';
import '../../../core/widgets/app_text_form_field.dart';
import 'widgets/osm_route_point_name_field.dart';
import 'widgets/route_map_coordinate_picker.dart';
import 'widgets/route_reviews_section.dart' show StarRatingDisplay;
import 'widgets/route_variants_section.dart';
import '../../../core/api/backend_api.dart';
import '../domain/route_rating.dart';

class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({super.key});

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen> {
  final _searchController = TextEditingController();
  final _distance = const Distance();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(routesProvider);
    final displayedAsync = ref.watch(displayedRoutesProvider);
    final difficulty = ref.watch(difficultyFilterProvider);
    final routeTypeFilter = ref.watch(routeTypeFilterProvider);
    final durationMaxFilter = ref.watch(durationMaxFilterProvider);
    final ascentMaxFilter = ref.watch(ascentMaxFilterProvider);
    final sort = ref.watch(routeSortProvider);

    final activeFiltersCount = _activeFiltersCount(
      difficulty,
      routeTypeFilter,
      durationMaxFilter,
      ascentMaxFilter,
      sort,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F2),
      appBar: AppBar(
        backgroundColor: AppTheme.toolbarBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Маршрути',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _showAddRouteDialog(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Додати'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchController,
              maxLength: 120,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                  null,
              onChanged: (value) {
                final err = FormValidators.searchQuery(value);
                if (err == null) {
                  ref.read(searchQueryProvider.notifier).state = value;
                }
              },
              decoration: InputDecoration(
                hintText: 'Пошук за назвою маршруту',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: () => _showFiltersSheet(context, ref),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF2E7D32)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.tune),
                        if (activeFiltersCount > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFF2E7D32),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$activeFiltersCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    label: const Text('Фільтри'),
                  ),
                ),
                const SizedBox(width: 10),
                _RouteSortIconButton(
                  sort: sort,
                  onSelected: (v) =>
                      ref.read(routeSortProvider.notifier).state = v,
                ),
              ],
            ),
          ),
          Expanded(
            child: displayedAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Помилка: $e'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        ref.invalidate(routesProvider);
                        ref.invalidate(displayedRoutesProvider);
                      },
                      child: const Text('Спробувати знову'),
                    ),
                  ],
                ),
              ),
              data: (items) => items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.terrain,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'Маршрутів поки немає',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Натисніть + щоб додати перший',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _RouteCard(
                          route: item.route,
                          ratingStats: item.stats,
                          onOpen: () => context.push(
                            '/routes/detail/${item.route.id}',
                          ),
                          onEdit: () => unawaited(
                            _showEditRouteDialog(context, item.route),
                          ),
                          onDelete: () =>
                              _deleteRoute(context, item.route),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  int _activeFiltersCount(
    String difficulty,
    String routeType,
    double? durationMax,
    int? ascentMax,
    String sort,
  ) {
    var n = 0;
    if (difficulty != 'all') n++;
    if (routeType != 'all') n++;
    if (durationMax != null) n++;
    if (ascentMax != null) n++;
    if (sort != 'newest') n++;
    return n;
  }

  void _showFiltersSheet(BuildContext context, WidgetRef ref) {
    final rt = <String>[ref.read(routeTypeFilterProvider)];
    final durationController = TextEditingController(
      text: ref.read(durationMaxFilterProvider)?.toString() ?? '',
    );
    final ascentController = TextEditingController(
      text: ref.read(ascentMaxFilterProvider)?.toString() ?? '',
    );
    final diff = <String>[ref.read(difficultyFilterProvider)];
    var sortValue = ref.read(routeSortProvider);
    final filterFormKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModal) {
          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: filterFormKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Фільтри',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Складність',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SheetDiffPill(
                        label: 'Всі',
                        selected: diff[0] == 'all',
                        onTap: () => setModal(() => diff[0] = 'all'),
                      ),
                      _SheetDiffPill(
                        label: 'Легкі',
                        selected: diff[0] == 'easy',
                        onTap: () => setModal(() => diff[0] = 'easy'),
                      ),
                      _SheetDiffPill(
                        label: 'Середні',
                        selected: diff[0] == 'medium',
                        onTap: () => setModal(() => diff[0] = 'medium'),
                      ),
                      _SheetDiffPill(
                        label: 'Важкі',
                        selected: diff[0] == 'hard',
                        onTap: () => setModal(() => diff[0] = 'hard'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: rt[0],
                    decoration: _inputDecoration('Вид маршруту'),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('Усі види'),
                      ),
                      ...RouteModel.storedRouteTypeKeys.map(
                        (k) => DropdownMenuItem<String>(
                          value: k,
                          child: Text(RouteModel.labelUkForRouteType(k)),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setModal(() => rt[0] = value ?? 'all'),
                  ),
                  const SizedBox(height: 12),
                  AppTextFormField(
                    controller: durationController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: FormValidators.filterMaxDuration,
                    decoration: _inputDecoration('Макс. тривалість (год)'),
                  ),
                  const SizedBox(height: 12),
                  AppTextFormField(
                    controller: ascentController,
                    keyboardType: TextInputType.number,
                    validator: FormValidators.filterMaxAscent,
                    decoration: _inputDecoration('Макс. перепад висот (м)'),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Сортування',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: sortValue,
                    decoration: _inputDecoration('Порядок'),
                    items: const [
                      DropdownMenuItem(
                        value: 'newest',
                        child: Text('Спочатку новіші'),
                      ),
                      DropdownMenuItem(
                        value: 'rating_desc',
                        child: Text('За рейтингом (від вищого)'),
                      ),
                      DropdownMenuItem(
                        value: 'rating_asc',
                        child: Text('За рейтингом (від нижчого)'),
                      ),
                    ],
                    onChanged: (v) => sortValue = v ?? 'newest',
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            diff[0] = 'all';
                            rt[0] = 'all';
                            sortValue = 'newest';
                            durationController.clear();
                            ascentController.clear();
                            ref.read(difficultyFilterProvider.notifier).state =
                                'all';
                            ref.read(routeTypeFilterProvider.notifier).state =
                                'all';
                            ref.read(durationMaxFilterProvider.notifier).state =
                                null;
                            ref.read(ascentMaxFilterProvider.notifier).state =
                                null;
                            ref.read(routeSortProvider.notifier).state =
                                'newest';
                            Navigator.pop(sheetContext);
                          },
                          child: const Text('Скинути все'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            if (!(filterFormKey.currentState?.validate() ??
                                false)) {
                              return;
                            }
                            final durationText = durationController.text
                                .replaceAll(',', '.')
                                .trim();
                            final ascentText = ascentController.text.trim();
                            final durationValue = durationText.isEmpty
                                ? null
                                : double.tryParse(durationText);
                            final ascentValue = ascentText.isEmpty
                                ? null
                                : int.tryParse(ascentText);
                            ref.read(difficultyFilterProvider.notifier).state =
                                diff[0];
                            ref.read(routeTypeFilterProvider.notifier).state =
                                rt[0];
                            ref.read(durationMaxFilterProvider.notifier).state =
                                durationValue;
                            ref.read(ascentMaxFilterProvider.notifier).state =
                                ascentValue;
                            ref.read(routeSortProvider.notifier).state =
                                sortValue;
                            Navigator.pop(sheetContext);
                          },
                          child: const Text('Застосувати'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showEditRouteDialog(BuildContext context, RouteModel route) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RouteEditorScreen(route: route),
      ),
    );
  }

  Future<void> _deleteRoute(BuildContext context, RouteModel route) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Видалити маршрут'),
        content: Text('Видалити маршрут "${route.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Скасувати'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;
    try {
      await ref.read(routesRepositoryProvider).deleteRoute(route.id);
      ref
        ..invalidate(routesProvider)
        ..invalidate(displayedRoutesProvider)
        ..invalidate(myPublicRoutesProvider)
        ..invalidate(myPrivateRoutesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Маршрут видалено')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Помилка видалення: $e')),
        );
      }
    }
  }

  Future<void> _showAddRouteDialog(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const RouteEditorScreen(),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}

void _disposePointDrafts(List<_RoutePointDraft> points) {
  for (final p in points) {
    p.dispose();
  }
}

List<_RoutePointDraft> _draftsFromWaypoints(List<RouteWaypoint>? waypoints) {
  if (waypoints == null || waypoints.isEmpty) {
    return [
      _RoutePointDraft(pointType: 'start'),
      _RoutePointDraft(pointType: 'finish'),
    ];
  }
  return waypoints
      .map(
        (w) => _RoutePointDraft(
          pointType: w.pointType,
          name: w.name,
          lat: w.position.latitude,
          lon: w.position.longitude,
          alt: w.altitudeM,
        ),
      )
      .toList();
}

class _RoutePointDraft {

  final String pointType;
  final TextEditingController nameController;
  final TextEditingController latController;
  final TextEditingController lonController;
  final TextEditingController altController;

  _RoutePointDraft({
    required this.pointType,
    String? name,
    double? lat,
    double? lon,
    int? alt,
  })  : nameController = TextEditingController(text: name ?? ''),
        latController = TextEditingController(
          text: lat != null ? lat.toStringAsFixed(6) : '',
        ),
        lonController = TextEditingController(
          text: lon != null ? lon.toStringAsFixed(6) : '',
        ),
        altController = TextEditingController(text: alt?.toString() ?? '');

  double? get lat => double.tryParse(latController.text.replaceAll(',', '.'));
  double? get lon => double.tryParse(lonController.text.replaceAll(',', '.'));
  int? get alt => int.tryParse(altController.text.trim());
  String get name => nameController.text.trim();

  void dispose() {
    nameController.dispose();
    latController.dispose();
    lonController.dispose();
    altController.dispose();
  }
}

class RouteComputedStats {
  final double distanceKm;
  final int ascentM;
  final int descentM;
  final double durationH;
  final int? elevationRangeM;
  final String? ascentHint;

  const RouteComputedStats({
    required this.distanceKm,
    required this.ascentM,
    this.descentM = 0,
    required this.durationH,
    this.elevationRangeM,
    this.ascentHint,
  });
}

RouteComputedStats _computeFromPoints(
  List<_RoutePointDraft> points,
  Distance distance,
) {
  final coords = points
      .map((p) => (p.lat != null && p.lon != null) ? (p.lat!, p.lon!, p.alt) : null)
      .whereType<(double, double, int?)>()
      .toList();

  final alts = coords.map((c) => c.$3).whereType<int>().toList();

  final segments = <HikeSegmentInput>[];
  for (var i = 1; i < coords.length; i++) {
    final prev = coords[i - 1];
    final cur = coords[i];
    final segMeters = distance.as(
      LengthUnit.Meter,
      LatLng(prev.$1, prev.$2),
      LatLng(cur.$1, cur.$2),
    );
    int? delta;
    if (prev.$3 != null && cur.$3 != null) {
      delta = cur.$3! - prev.$3!;
    }
    segments.add(HikeSegmentInput(distanceM: segMeters, deltaAltM: delta));
  }

  final estimate = HikeDurationEstimate.fromSegments(segments);

  int? elevationRange;
  final hintParts = <String>[];
  if (estimate.durationHint != null) {
    hintParts.add(estimate.durationHint!);
  }
  if (alts.length >= 2) {
    final minAlt = alts.reduce((a, b) => a < b ? a : b);
    final maxAlt = alts.reduce((a, b) => a > b ? a : b);
    elevationRange = maxAlt - minAlt;
    if (estimate.ascentM == 0 &&
        estimate.descentM == 0 &&
        elevationRange > 0) {
      hintParts.add(
        'Різниця висот точок: $elevationRange м — додайте висоти для точнішого часу',
      );
    }
  } else if (coords.length >= 2 && alts.length < 2) {
    hintParts.add(
      'Додайте висоти точок — час врахує підйоми, спуски та втомливість',
    );
  }

  return RouteComputedStats(
    distanceKm: estimate.distanceKm,
    ascentM: estimate.ascentM,
    descentM: estimate.descentM,
    durationH: estimate.durationH,
    elevationRangeM: elevationRange,
    ascentHint: hintParts.isEmpty ? null : hintParts.join(' '),
  );
}

String? _routeTitleFromPointDrafts(List<_RoutePointDraft> points) {
  _RoutePointDraft? find(String type) {
    for (final p in points) {
      if (p.pointType == type) return p;
    }
    return null;
  }

  final startName = find('start')?.name.trim() ?? '';
  final finishName = find('finish')?.name.trim() ?? '';
  if (startName.isEmpty || finishName.isEmpty) return null;
  return '$startName — $finishName';
}

bool _hasValidStartFinish(List<_RoutePointDraft> points) {
  final start = points.firstWhere(
    (p) => p.pointType == 'start',
    orElse: () => _RoutePointDraft(pointType: 'start'),
  );
  final finish = points.firstWhere(
    (p) => p.pointType == 'finish',
    orElse: () => _RoutePointDraft(pointType: 'finish'),
  );
  return start.lat != null &&
      start.lon != null &&
      finish.lat != null &&
      finish.lon != null;
}

String _pointTypeForDatabase(String pointType) {
  return pointType == 'waypoint' ? 'viewpoint' : pointType;
}

List<Map<String, dynamic>> _toDbPoints(
  String routeId,
  List<_RoutePointDraft> points,
) {
  return _toSaveRoutePoints(points).map((p) {
    return {...p, 'route_id': routeId};
  }).toList();
}

List<Map<String, dynamic>> _toSaveRoutePoints(List<_RoutePointDraft> points) {
  final result = <Map<String, dynamic>>[];
  var sort = 0;
  for (final p in points) {
    final lat = p.lat;
    final lon = p.lon;
    if (lat == null || lon == null) continue;
    final dbType = _pointTypeForDatabase(p.pointType);
    result.add({
      'name': p.name.isEmpty
          ? (p.pointType == 'start'
              ? 'Старт'
              : p.pointType == 'finish'
                  ? 'Фініш'
                  : 'Точка')
          : p.name,
      'latitude': lat,
      'longitude': lon,
      'altitude_m': p.alt,
      'point_type': dbType,
      'sort_order': sort++,
    });
  }
  return result;
}

class _PointsEditor extends StatefulWidget {
  final List<_RoutePointDraft> points;
  final VoidCallback onChanged;

  const _PointsEditor({
    required this.points,
    required this.onChanged,
  });

  @override
  State<_PointsEditor> createState() => _PointsEditorState();
}

class _PointsEditorState extends State<_PointsEditor> {
  @override
  Widget build(BuildContext context) {
    final points = widget.points;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Точки маршруту',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    points.insert(
                      points.length - 1,
                      _RoutePointDraft(pointType: 'viewpoint'),
                    );
                  });
                  widget.onChanged();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Додати'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < points.length; i++) ...[
            _PointRow(
              point: points[i],
              allPoints: points,
              canRemove: points[i].pointType != 'start' &&
                  points[i].pointType != 'finish',
              onRemove: () {
                setState(() => points.removeAt(i));
                widget.onChanged();
              },
              onChanged: widget.onChanged,
            ),
            if (i != points.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _PointRow extends StatefulWidget {
  final _RoutePointDraft point;
  final List<_RoutePointDraft> allPoints;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _PointRow({
    required this.point,
    required this.allPoints,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<_PointRow> createState() => _PointRowState();
}

class _PointRowState extends State<_PointRow> {
  static final _elevationLookup = ElevationLookupService();
  Timer? _elevationDebounce;
  bool _elevationLoading = false;

  _RoutePointDraft get point => widget.point;

  @override
  void dispose() {
    _elevationDebounce?.cancel();
    super.dispose();
  }

  Future<void> _resolveElevation() async {
    final lat = point.lat;
    final lon = point.lon;
    if (lat == null || lon == null) {
      point.altController.clear();
      return;
    }
    if (mounted) setState(() => _elevationLoading = true);
    final ele = await _elevationLookup.fetchElevationM(lat, lon);
    if (!mounted) return;
    if (ele != null) {
      point.altController.text = ele.toString();
    } else {
      point.altController.clear();
    }
    setState(() => _elevationLoading = false);
    widget.onChanged();
  }

  void _scheduleElevationLookup() {
    _elevationDebounce?.cancel();
    _elevationDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_resolveElevation());
    });
  }

  void _onCoordsEdited() {
    widget.onChanged();
    _scheduleElevationLookup();
  }

  String _referenceLabel(_RoutePointDraft p, int index) {
    if (p.pointType == 'start') return 'Старт';
    if (p.pointType == 'finish') return 'Фініш';
    final name = p.name;
    if (name.isNotEmpty) return name;
    return 'Точка ${index + 1}';
  }

  List<RouteMapReferencePoint> _otherPointsForMap() {
    final out = <RouteMapReferencePoint>[];
    for (var i = 0; i < widget.allPoints.length; i++) {
      final p = widget.allPoints[i];
      if (identical(p, point)) continue;
      final lat = p.lat;
      final lon = p.lon;
      if (lat == null || lon == null) continue;
      out.add(
        RouteMapReferencePoint(
          position: LatLng(lat, lon),
          label: _referenceLabel(p, i),
          pointType: p.pointType,
        ),
      );
    }
    return out;
  }

  Future<void> _pickCoordinatesOnMap(BuildContext context) async {
    final lat = point.lat;
    final lon = point.lon;
    final initial = (lat != null && lon != null) ? LatLng(lat, lon) : null;
    final picked = await RouteMapCoordinatePickerScreen.show(
      context,
      initialCenter: initial,
      initialSelection: initial,
      existingPoints: _otherPointsForMap(),
    );
    if (picked == null) return;
    point.latController.text = picked.latitude.toStringAsFixed(6);
    point.lonController.text = picked.longitude.toStringAsFixed(6);
    await _resolveElevation();
  }

  @override
  Widget build(BuildContext context) {
    final label = point.pointType == 'start'
        ? 'Старт'
        : point.pointType == 'finish'
            ? 'Фініш'
            : 'Точка';
    final coordsRequired =
        point.pointType == 'start' || point.pointType == 'finish';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (widget.canRemove)
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.close),
                tooltip: 'Видалити точку',
              ),
          ],
        ),
        const SizedBox(height: 6),
        OsmRoutePointNameField(
          nameController: point.nameController,
          latController: point.latController,
          lonController: point.lonController,
          altController: point.altController,
          onCoordinatesApplied: () {
            widget.onChanged();
            unawaited(_resolveElevation());
          },
          nameRequired: false,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              onPressed: () => _pickCoordinatesOnMap(context),
              icon: const Icon(Icons.map_outlined),
              tooltip: 'Обрати на карті',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFE8F5E9),
                foregroundColor: const Color(0xFF2E7D32),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextFormField(
                controller: point.latController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => FormValidators.latitude(
                  v,
                  requiredField: coordsRequired,
                ),
                decoration: InputDecoration(
                  hintText: 'Lat',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                onChanged: (_) => _onCoordsEdited(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: point.lonController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => FormValidators.longitude(
                  v,
                  requiredField: coordsRequired,
                ),
                decoration: InputDecoration(
                  hintText: 'Lon',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                onChanged: (_) => _onCoordsEdited(),
              ),
            ),
          ],
        ),
        if (_elevationLoading || point.alt != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              if (_elevationLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.grey[600],
                  ),
                )
              else
                Icon(Icons.terrain, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                _elevationLoading
                    ? 'Визначення висоти…'
                    : 'Висота (авто): ${point.alt} м',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class RouteEditorScreen extends ConsumerStatefulWidget {
  const RouteEditorScreen({
    super.key,
    this.route,
  });

  final RouteModel? route;

  @override
  ConsumerState<RouteEditorScreen> createState() => _RouteEditorScreenState();
}

class _RouteEditorScreenState extends ConsumerState<RouteEditorScreen> {
  static const _distance = Distance();

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _distanceController = TextEditingController();
  final _durationController = TextEditingController();
  final _ascentController = TextEditingController();

  String _selectedDifficulty = 'easy';
  String _selectedRouteType = 'linear';
  List<_RoutePointDraft> _points = [
    _RoutePointDraft(pointType: 'start'),
    _RoutePointDraft(pointType: 'finish'),
  ];

  bool _loading = false;
  bool _saving = false;
  bool _initialized = false;
  String? _ascentStatsHint;
  bool _variantsLoading = false;
  List<RouteVariant> _variants = [];
  int? _selectedVariantIndex;
  RouteVariant? _chosenVariant;
  bool _isPublic = true;
  bool _titleManuallyEdited = false;

  bool get _isEdit => widget.route != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadForEdit());
    } else {
      _initialized = true;
    }
  }

  Future<void> _loadForEdit() async {
    final route = widget.route!;
    RouteDetail? detail;
    try {
      detail =
          await ref.read(routesRepositoryProvider).getRouteDetail(route.id);
    } catch (_) {
      detail = null;
    }
    if (!mounted) return;

    _titleController.text = route.title;
    _descController.text = route.description;
    _selectedDifficulty = RouteModel.normalizeDifficulty(route.difficulty);
    _selectedRouteType = RouteModel.normalizeStoredRouteType(route.routeType);
    _isPublic = route.isPublic;
    _disposePointDrafts(_points);
    _points = _draftsFromWaypoints(detail?.waypoints);
    _applyStatsToFields();

    setState(() {
      _loading = false;
      _initialized = true;
    });
  }

  void _applyStatsToFields() {
    final stats = _computeFromPoints(_points, _distance);
    _distanceController.text = stats.distanceKm.toStringAsFixed(2);
    _durationController.text = stats.durationH.toStringAsFixed(1);
    _ascentController.text = stats.ascentM.toString();
    _ascentStatsHint = stats.ascentHint;
  }

  void _onPointsChanged() {
    setState(() {
      _applyStatsToFields();
      if (!_isEdit) _applyAutoRouteTitle();
      _variants = [];
      _selectedVariantIndex = null;
      _chosenVariant = null;
    });
  }

  void _applyAutoRouteTitle() {
    if (_titleManuallyEdited) return;
    final auto = _routeTitleFromPointDrafts(_points);
    if (auto != null) {
      _titleController.text = auto;
    } else {
      _titleController.clear();
    }
  }

  List<LatLng> _waypointsForRouting() {
    final out = <LatLng>[];
    for (final p in _points) {
      final lat = p.lat;
      final lon = p.lon;
      if (lat != null && lon != null) out.add(LatLng(lat, lon));
    }
    return out;
  }

  void _applyVariant(int index) {
    if (index < 0 || index >= _variants.length) return;
    final v = _variants[index];
    _distanceController.text = v.distanceKm.toStringAsFixed(2);
    _durationController.text = v.durationH.toStringAsFixed(1);
    _ascentController.text = v.ascentM.toString();
    _ascentStatsHint = v.ascentM == 0
        ? 'Набір висоти з маршрутизатора; для точніших даних додайте висоти точок'
        : null;
    _selectedDifficulty = RouteModel.normalizeDifficulty(v.difficulty);
    _selectedVariantIndex = index;
    _chosenVariant = v;
  }

  Future<void> _suggestVariants() async {
    if (!_hasValidStartFinish(_points)) {
      _snack('Додайте координати старту і фінішу');
      return;
    }
    final wps = _waypointsForRouting();
    if (wps.length < 2) {
      _snack('Потрібно щонайменше дві точки з координатами');
      return;
    }

    setState(() => _variantsLoading = true);
    try {
      final list = await RouteVariantsApi().fetchVariants(wps);
      if (!mounted) return;
      if (list.isEmpty) {
        _snack('Не вдалося побудувати маршрут між цими точками');
        return;
      }
      setState(() {
        _variants = list;
        _applyVariant(0);
      });
      final msg = switch (list.length) {
        0 => 'Не вдалося побудувати маршрут',
        1 => 'Знайдено 1 варіант (інші стежки роутер не відрізнив)',
        2 => 'Знайдено 2 варіанти — оберіть підходящий',
        _ => 'Знайдено ${list.length} варіанти — оберіть підходящий',
      };
      if (list.isNotEmpty) _snack(msg);
    } on BackendApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Помилка побудови: $e');
    } finally {
      if (mounted) setState(() => _variantsLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _distanceController.dispose();
    _durationController.dispose();
    _ascentController.dispose();
    _disposePointDrafts(_points);
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_hasValidStartFinish(_points)) {
      _snack('Додайте старт і фініш: координати');
      return;
    }

    setState(() => _saving = true);
    try {
      final saveApi = SaveRouteApi();
      final points = _toSaveRoutePoints(_points);
      final title = _titleController.text.trim();
      final description = _descController.text.trim();

      String routeId;
      try {
        if (_isEdit) {
          routeId = widget.route!.id;
          await saveApi.updateRoute(
            routeId: routeId,
            title: title,
            routeType: _selectedRouteType,
            description: description,
            difficulty: _selectedDifficulty,
            points: points,
            isPublic: _isPublic,
            chosenRoute: _chosenVariant,
          );
        } else {
          routeId = await saveApi.createRoute(
            title: title,
            routeType: _selectedRouteType,
            description: description,
            difficulty: _selectedDifficulty,
            points: points,
            isPublic: _isPublic,
            chosenRoute: _chosenVariant,
          );
        }
      } catch (_) {
        final stats = _computeFromPoints(_points, _distance);
        final repo = ref.read(routesRepositoryProvider);
        if (_isEdit) {
          routeId = widget.route!.id;
          await repo.updateRoute(routeId, {
            'title': title,
            'route_type': _selectedRouteType,
            'description': description,
            'distance_km': stats.distanceKm,
            'duration_h': stats.durationH,
            'ascent_m': stats.ascentM,
            'difficulty': _selectedDifficulty,
            'is_public': _isPublic,
          });
          await repo.replaceRoutePoints(routeId, _toDbPoints(routeId, _points));
        } else {
          final authorId = Supabase.instance.client.auth.currentUser!.id;
          routeId = await repo.addRouteReturningId({
            'title': title,
            'route_type': _selectedRouteType,
            'description': description,
            'distance_km': stats.distanceKm,
            'duration_h': stats.durationH,
            'ascent_m': stats.ascentM,
            'difficulty': _selectedDifficulty,
            'is_public': _isPublic,
            'author_id': authorId,
          });
          await repo.replaceRoutePoints(routeId, _toDbPoints(routeId, _points));
        }
      }

      ref
        ..invalidate(routesProvider)
        ..invalidate(displayedRoutesProvider)
        ..invalidate(myPublicRoutesProvider)
        ..invalidate(myPrivateRoutesProvider)
        ..invalidate(routeDetailProvider(routeId));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack(_isEdit ? 'Помилка редагування: $e' : 'Помилка: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F2),
      appBar: AppBar(
        backgroundColor: AppTheme.toolbarBackground,
        surfaceTintColor: Colors.transparent,
        title: Text(_isEdit ? 'Редагувати маршрут' : 'Новий маршрут'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_initialized
              ? const SizedBox.shrink()
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTextFormField(
                        controller: _titleController,
                        validator: FormValidators.title,
                        onChanged: (_) => _titleManuallyEdited = true,
                        decoration: _routeEditorDecoration('Назва маршруту *').copyWith(
                          helperText: !_isEdit &&
                                  _routeTitleFromPointDrafts(_points) == null
                              ? 'Вкажіть назви старту та фінішу або введіть назву вручну'
                              : null,
                          helperMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Доступ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('Публічний'),
                            icon: Icon(Icons.public, size: 18),
                          ),
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('Приватний'),
                            icon: Icon(Icons.lock_outline, size: 18),
                          ),
                        ],
                        selected: {_isPublic},
                        onSelectionChanged: _saving
                            ? null
                            : (selected) {
                                setState(() => _isPublic = selected.first);
                              },
                        style: ButtonStyle(
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? Colors.white
                                : const Color(0xFF2E7D32),
                          ),
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? const Color(0xFF2E7D32)
                                : Colors.white,
                          ),
                        ),
                      ),
                      if (!_isPublic) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Лише для вас — у профілі, розділ «Мої маршрути» → «Приватні»',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Вид маршруту',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: RouteModel.storedRouteTypeKeys.map((k) {
                          return ChoiceChip(
                            label: Text(RouteModel.labelUkForRouteType(k)),
                            selected: _selectedRouteType == k,
                            onSelected: _saving
                                ? null
                                : (selected) {
                                    if (!selected) return;
                                    setState(
                                      () => _selectedRouteType =
                                          RouteModel.normalizeStoredRouteType(
                                            k,
                                          ),
                                    );
                                  },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      AppTextFormField(
                        controller: _descController,
                        maxLines: 3,
                        validator: (v) =>
                            FormValidators.description(v, requiredField: false),
                        decoration: _routeEditorDecoration('Опис'),
                      ),
                      const SizedBox(height: 16),
                      _PointsEditor(
                        points: _points,
                        onChanged: _onPointsChanged,
                      ),
                      const SizedBox(height: 16),
                      RouteVariantsSection(
                        variants: _variants,
                        loading: _variantsLoading,
                        selectedIndex: _selectedVariantIndex,
                        disabled: _saving,
                        onSuggest: _suggestVariants,
                        onSelect: (i) => setState(() => _applyVariant(i)),
                      ),
                      const SizedBox(height: 16),
                      _RouteAutoStatsSection(
                        distanceController: _distanceController,
                        durationController: _durationController,
                        ascentController: _ascentController,
                        ascentHint: _ascentStatsHint,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Складність',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      if (_chosenVariant != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Підставлено з обраного варіанту — можна змінити вручну',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: RouteModel.storedDifficultyKeys.map((k) {
                          return ChoiceChip(
                            label: Text(_difficultyLabel(k)),
                            selected: _selectedDifficulty == k,
                            onSelected: _saving
                                ? null
                                : (selected) {
                                    if (!selected) return;
                                    setState(
                                      () => _selectedDifficulty =
                                          RouteModel.normalizeDifficulty(k),
                                    );
                                  },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _isEdit ? 'Зберегти зміни' : 'Зберегти маршрут',
                              ),
                      ),
                    ],
                  ),
                  ),
                ),
    );
  }

  static String _difficultyLabel(String key) => switch (key) {
        'easy' => 'Легкий',
        'medium' => 'Середній',
        'hard' => 'Важкий',
        _ => key,
      };
}

InputDecoration _routeEditorDecoration(String label) {
  return InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

class _RouteAutoStatsSection extends StatelessWidget {
  final TextEditingController distanceController;
  final TextEditingController durationController;
  final TextEditingController ascentController;
  final String? ascentHint;

  const _RouteAutoStatsSection({
    required this.distanceController,
    required this.durationController,
    required this.ascentController,
    this.ascentHint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Параметри маршруту',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _AutoStatField(
                      label: 'Відстань',
                      controller: distanceController,
                      suffix: 'км',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _AutoStatField(
                      label: 'Тривалість',
                      controller: durationController,
                      suffix: 'год',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _AutoStatField(
                label: 'Набір висоти',
                controller: ascentController,
                suffix: 'м',
              ),
            ],
          ),
        ),
        if (ascentHint != null && ascentHint!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            ascentHint!,
            style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.35),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'Тривалість: відстань, підйоми, спуски та втома на довгих ділянках. '
          'Набір висоти — сума підйомів між точками.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.35),
        ),
      ],
    );
  }
}

class _AutoStatField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String suffix;

  const _AutoStatField({
    required this.label,
    required this.controller,
    required this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      enableInteractiveSelection: false,
      decoration: InputDecoration(
        labelText: '$label (авто)',
        suffixText: suffix,
        filled: true,
        fillColor: const Color(0xFFF5F7F4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final RouteModel route;
  final RouteRatingAggregate? ratingStats;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RouteCard({
    required this.route,
    this.ratingStats,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isAuthor = currentUserId != null && route.authorId == currentUserId;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      route.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: route.difficultyColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: route.difficultyColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      route.difficultyLabel,
                      style: TextStyle(
                        color: route.difficultyColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isAuthor)
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') onEdit();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Редагувати'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Видалити'),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.alt_route, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      route.routeTypeLabelUk,
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _RouteCardRating(stats: ratingStats),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatItem(
                    icon: Icons.straighten,
                    value: '${route.distanceKm} км',
                  ),
                  const SizedBox(width: 16),
                  _StatItem(
                    icon: Icons.schedule,
                    value: '${route.durationH} год',
                  ),
                  const SizedBox(width: 16),
                  _StatItem(
                    icon: Icons.trending_up,
                    value: '${route.ascentM} м',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteSortIconButton extends StatelessWidget {
  final String sort;
  final ValueChanged<String> onSelected;

  const _RouteSortIconButton({
    required this.sort,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF2E7D32)),
      ),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<String>(
        tooltip: 'Сортування',
        padding: EdgeInsets.zero,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.sort, color: Color(0xFF2E7D32)),
            if (sort != 'newest')
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2E7D32),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        onSelected: onSelected,
        itemBuilder: (context) => [
          _sortItem('newest', 'Спочатку новіші'),
          _sortItem('rating_desc', 'За рейтингом (від вищого)'),
          _sortItem('rating_asc', 'За рейтингом (від нижчого)'),
        ],
      ),
      ),
    );
  }

  PopupMenuItem<String> _sortItem(String value, String label) {
    final selected = sort == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: selected
                ? const Icon(Icons.check, size: 18, color: Color(0xFF2E7D32))
                : null,
          ),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _RouteCardRating extends StatelessWidget {
  final RouteRatingAggregate? stats;

  const _RouteCardRating({this.stats});

  @override
  Widget build(BuildContext context) {
    final count = stats?.count ?? 0;
    if (count == 0) {
      return Row(
        children: [
          Icon(Icons.star_outline, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 6),
          Text(
            'Без оцінок',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      );
    }
    return Row(
      children: [
        StarRatingDisplay(rating: stats!.averageRating, size: 16),
        const SizedBox(width: 6),
        Text(
          stats!.averageRating.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2E7D32),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '(${RouteReviewsSummary.reviewsCountLabel(count)})',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
      ],
    );
  }
}

class _SheetDiffPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SheetDiffPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2E7D32) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF2E7D32) : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey[800],
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;

  const _StatItem({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(color: Colors.grey[700], fontSize: 13),
        ),
      ],
    );
  }
}
