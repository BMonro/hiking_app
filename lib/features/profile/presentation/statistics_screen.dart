import 'package:fl_chart/fl_chart.dart';

import '../../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Агрегат за весь час (VIEW profile_stats).
final profileStatsAllTimeProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return null;

  final row = await client
      .from('profile_stats')
      .select('total_hikes, total_distance_km, total_ascent_m')
      .eq('user_id', userId)
      .maybeSingle();
  if (row == null) return null;
  return Map<String, dynamic>.from(row as Map);
});

/// Журнал за рік (графіки, рекорди за місяць).
final journalEntriesForYearProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>((ref, year) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return [];

  final data = await client
      .from('journal_entries')
      .select(
        'id, date, title, actual_distance_km, actual_duration_h, actual_ascent_m',
      )
      .eq('user_id', userId)
      .gte('date', '$year-01-01')
      .lte('date', '$year-12-31')
      .order('date', ascending: true);

  final list = data as List<dynamic>;
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

class _StatsTheme {
  static const bg = Color(0xFFFBF9F1);
  static const primary = Color(0xFF24A175);
  static const primaryDark = Color(0xFF1E8A62);
  static const mint = Color(0xFFB8E6D5);
  static const orange = Color(0xFFD3603B);
  static const cardBorder = Color(0xFFE8E4DC);
}

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;

  List<int> _yearItems() {
    final now = DateTime.now().year;
    const start = 2020;
    return [for (var y = now; y >= start; y--) y];
  }

  bool get _canGoNextMonth {
    final now = DateTime.now();
    return _year < now.year ||
        (_year == now.year && _month < now.month);
  }

  void _shiftMonth(int delta) {
    var m = _month + delta;
    var y = _year;
    if (m > 12) {
      m = 1;
      y++;
    } else if (m < 1) {
      m = 12;
      y--;
    }
    final now = DateTime.now();
    if (y > now.year || (y == now.year && m > now.month)) {
      y = now.year;
      m = now.month;
    }
    if (y < 2020) {
      y = 2020;
      m = 1;
    }
    setState(() {
      _year = y;
      _month = m;
    });
  }

  void _onYearChanged(int? y) {
    if (y == null) return;
    final now = DateTime.now();
    var month = _month;
    if (y == now.year && month > now.month) {
      month = now.month;
    }
    setState(() {
      _year = y;
      _month = month;
    });
  }

  Future<void> _refreshStats() async {
    ref.invalidate(profileStatsAllTimeProvider);
    ref.invalidate(journalEntriesForYearProvider(_year));
    await Future.wait([
      ref.read(profileStatsAllTimeProvider.future),
      ref.read(journalEntriesForYearProvider(_year).future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(journalEntriesForYearProvider(_year));
    final allTimeAsync = ref.watch(profileStatsAllTimeProvider);

    return Scaffold(
      backgroundColor: _StatsTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.toolbarBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/profile');
            }
          },
        ),
        title: const Text(
          'Статистика',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _StatsTheme.cardBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _year,
                    borderRadius: BorderRadius.circular(12),
                    items: _yearItems()
                        .map(
                          (y) => DropdownMenuItem(
                            value: y,
                            child: Text('$y'),
                          ),
                        )
                        .toList(),
                    onChanged: _onYearChanged,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _MonthNavigator(
              year: _year,
              month: _month,
              canGoNext: _canGoNextMonth,
              onPrevious: () => _shiftMonth(-1),
              onNext: _canGoNextMonth ? () => _shiftMonth(1) : null,
            ),
          ),
          Expanded(
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Не вдалося завантажити журнал: $e',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _refreshStats,
                        child: const Text('Спробувати знову'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (entries) {
                final yearStats = _computeYearStats(entries);
                final monthEntries =
                    _entriesForMonth(entries, _year, _month);
                final monthStats = _computeYearStats(monthEntries);
                final monthLabel =
                    '${_monthNames[_month - 1].toLowerCase()} $_year';

                return RefreshIndicator(
                  onRefresh: _refreshStats,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        allTimeAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                          data: (allTime) {
                            if (allTime == null) return const SizedBox.shrink();
                            final hikesRaw = allTime['total_hikes'];
                            final hikesCount = hikesRaw is int
                                ? hikesRaw
                                : int.tryParse('$hikesRaw') ?? 0;
                            final km = _asDouble(allTime['total_distance_km']);
                            final asc = _asDouble(allTime['total_ascent_m']);
                            if (hikesCount == 0 &&
                                (km ?? 0) <= 0 &&
                                (asc ?? 0) <= 0) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _AllTimeBanner(
                                hikes: hikesCount,
                                km: km ?? 0,
                                ascentM: asc ?? 0,
                              ),
                            );
                          },
                        ),
                        _SectionTitle(title: 'Підсумок за $_year рік'),
                        const SizedBox(height: 12),
                        _SummaryCards(stats: yearStats),
                        if (yearStats.hikes == 0) ...[
                          const SizedBox(height: 12),
                          _EmptyHint(
                            text:
                                'У журналі немає записів за $_year рік. Додайте похід у розділі «Журнал походів» або завершіть навігацію маршруту.',
                          ),
                        ],
                        const SizedBox(height: 24),
                        _SectionTitle(title: 'Активність за рік'),
                        const SizedBox(height: 12),
                        _YearlyActivityChart(
                          year: _year,
                          stats: yearStats,
                          selectedMonth: _month,
                        ),
                        const SizedBox(height: 24),
                        _SectionTitle(title: 'За $monthLabel'),
                        const SizedBox(height: 12),
                        _ElevationChart(
                          stats: monthStats,
                          emptyHint:
                              'Немає записів за $monthLabel',
                        ),
                        const SizedBox(height: 24),
                        _SectionTitle(title: 'Рекорди за $monthLabel'),
                        const SizedBox(height: 12),
                        _RecordsCard(stats: monthStats),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _YearStats {
  _YearStats({
    required this.hikes,
    required this.totalKm,
    required this.totalHours,
    required this.monthlyHikes,
    required this.ascentSpots,
    required this.peakIndex,
    required this.maxAscentM,
    required this.peakLabel,
    this.longestTripKm,
    this.longestTripLabel,
    this.maxAscentEntryLabel,
    this.longestDayHours,
  });

  final int hikes;
  final double totalKm;
  final double totalHours;
  final List<int> monthlyHikes;
  final List<FlSpot> ascentSpots;
  final int peakIndex;
  final double maxAscentM;
  final String peakLabel;
  final double? longestTripKm;
  final String? longestTripLabel;
  final String? maxAscentEntryLabel;
  final double? longestDayHours;
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _yearFromEntry(Map<String, dynamic> e) {
  final d = e['date'];
  if (d == null) return null;
  if (d is DateTime) return d.year;
  final parts = d.toString().split('-');
  if (parts.isNotEmpty) return int.tryParse(parts[0]);
  return null;
}

int? _monthFromEntry(Map<String, dynamic> e) {
  final d = e['date'];
  if (d == null) return null;
  if (d is DateTime) return d.month;
  final s = d.toString();
  final parts = s.split('-');
  if (parts.length >= 2) return int.tryParse(parts[1]);
  return null;
}

List<Map<String, dynamic>> _entriesForMonth(
  List<Map<String, dynamic>> entries,
  int year,
  int month,
) {
  return entries
      .where((e) => _yearFromEntry(e) == year && _monthFromEntry(e) == month)
      .toList();
}

String _routeLabel(Map<String, dynamic> e) {
  final t = e['title'] as String?;
  if (t != null && t.isNotEmpty) return t;
  return '—';
}

_YearStats _computeYearStats(List<Map<String, dynamic>> entries) {
  final monthly = List<int>.filled(12, 0);

  double km = 0;
  double hours = 0;

  for (final e in entries) {
    final m = _monthFromEntry(e);
    if (m != null && m >= 1 && m <= 12) monthly[m - 1]++;

    km += _asDouble(e['actual_distance_km']) ?? 0;
    hours += _asDouble(e['actual_duration_h']) ?? 0;
  }

  final spots = <FlSpot>[];
  var peakI = 0;
  var maxA = 0.0;
  for (var i = 0; i < entries.length; i++) {
    final a = _asDouble(entries[i]['actual_ascent_m']) ?? 0;
    spots.add(FlSpot(i.toDouble(), a));
    if (a > maxA) {
      maxA = a;
      peakI = i;
    }
  }

  final peakTitle = entries.isEmpty
      ? ''
      : _routeLabel(entries[peakI >= entries.length ? 0 : peakI]);
  final peakLabel = entries.isEmpty
      ? 'Немає даних'
      : (maxA > 0
          ? '$peakTitle · ${maxA.round()} м'
          : 'Немає даних про набір висоти');

  Map<String, dynamic>? longestDistEntry;
  var bestKm = -1.0;
  Map<String, dynamic>? longestAscentEntry;
  var bestAsc = -1.0;
  Map<String, dynamic>? longestDayEntry;
  var bestH = -1.0;

  for (final e in entries) {
    final dk = _asDouble(e['actual_distance_km']);
    if (dk != null && dk > bestKm) {
      bestKm = dk;
      longestDistEntry = e;
    }
    final asc = _asDouble(e['actual_ascent_m']);
    if (asc != null && asc > bestAsc) {
      bestAsc = asc;
      longestAscentEntry = e;
    }
    final dh = _asDouble(e['actual_duration_h']);
    if (dh != null && dh > bestH) {
      bestH = dh;
      longestDayEntry = e;
    }
  }

  return _YearStats(
    hikes: entries.length,
    totalKm: km,
    totalHours: hours,
    monthlyHikes: monthly,
    ascentSpots: spots,
    peakIndex: peakI,
    maxAscentM: maxA,
    peakLabel: peakLabel,
    longestTripKm: longestDistEntry != null ? bestKm : null,
    longestTripLabel:
        longestDistEntry == null ? null : _routeLabel(longestDistEntry),
    maxAscentEntryLabel: longestAscentEntry != null && bestAsc > 0
        ? '${bestAsc.round()} м · ${_routeLabel(longestAscentEntry)}'
        : null,
    longestDayHours: longestDayEntry != null ? bestH : null,
  );
}

String _formatKm(double km) {
  if (km <= 0) return '0';
  if (km >= 100) return km.round().toString();
  final rounded = km.roundToDouble();
  if ((km - rounded).abs() < 0.05) return km.round().toString();
  return km.toStringAsFixed(1);
}

String _formatDurationHours(double h) {
  final totalMin = (h * 60).round();
  final hh = totalMin ~/ 60;
  final mm = totalMin % 60;
  return '$hh год $mm хв';
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.stats});

  final _YearStats stats;

  @override
  Widget build(BuildContext context) {
    final kmStr = _formatKm(stats.totalKm);
    final hoursRound = stats.totalHours.round();

    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            value: '${stats.hikes}',
            label: 'Походів',
            highlighted: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            value: kmStr,
            label: 'Кілометрів',
            highlighted: false,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            value: '${hoursRound}h',
            label: 'Годин',
            highlighted: false,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.value,
    required this.label,
    required this.highlighted,
  });

  final String value;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted ? _StatsTheme.primary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: highlighted
            ? null
            : Border.all(color: _StatsTheme.cardBorder, width: 1),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: _StatsTheme.primary.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: highlighted ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: highlighted
                    ? Colors.white.withValues(alpha: 0.95)
                    : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
    );
  }
}

class _AllTimeBanner extends StatelessWidget {
  const _AllTimeBanner({
    required this.hikes,
    required this.km,
    required this.ascentM,
  });

  final int hikes;
  final double km;
  final double ascentM;

  @override
  Widget build(BuildContext context) {
    final hikesStr = hikes.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _StatsTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _StatsTheme.mint),
      ),
      child: Text(
        'Усього в журналі: $hikesStr походів · ${_formatKm(km)} км · ${ascentM.round()} м набору',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _StatsTheme.cardBorder),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4),
      ),
    );
  }
}

const _monthNames = <String>[
  'Січень',
  'Лютий',
  'Березень',
  'Квітень',
  'Травень',
  'Червень',
  'Липень',
  'Серпень',
  'Вересень',
  'Жовтень',
  'Листопад',
  'Грудень',
];

const _monthShort = <String>[
  'Січ',
  'Лют',
  'Бер',
  'Кві',
  'Тра',
  'Чер',
  'Лип',
  'Сер',
  'Вер',
  'Жов',
  'Лис',
  'Гру',
];

class _MonthNavigator extends StatelessWidget {
  const _MonthNavigator({
    required this.year,
    required this.month,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  final int year;
  final int month;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final label = '${_monthNames[month - 1]} $year';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _StatsTheme.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Попередній місяць',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
              color: _StatsTheme.primaryDark,
            ),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Наступний місяць',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
              color: canGoNext ? _StatsTheme.primaryDark : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}

class _YearlyActivityChart extends StatelessWidget {
  const _YearlyActivityChart({
    required this.year,
    required this.stats,
    required this.selectedMonth,
  });

  final int year;
  final _YearStats stats;
  final int selectedMonth;

  @override
  Widget build(BuildContext context) {
    final counts = stats.monthlyHikes;
    final maxC =
        counts.isEmpty ? 0 : counts.reduce((a, b) => a > b ? a : b);
    final maxMonth = maxC > 0 ? counts.indexOf(maxC) : -1;
    final selectedIdx = selectedMonth - 1;
    final maxY = maxC <= 0 ? 1.0 : (maxC * 1.25).ceilToDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _StatsTheme.cardBorder),
      ),
      height: 220,
      child: maxC == 0
          ? Center(
              child: Text(
                'Немає записів у журналі за $year рік',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            )
          : BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= 12) return const SizedBox();
                        final isSelected = i == selectedIdx;
                        final isPeak = i == maxMonth && maxC > 0;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _monthShort[i],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected || isPeak
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? _StatsTheme.primary
                                  : isPeak
                                      ? _StatsTheme.primaryDark
                                      : Colors.grey[600],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(12, (i) {
                  final v = counts[i].toDouble();
                  final isSelected = i == selectedIdx;
                  final isPeak = i == maxMonth && maxC > 0 && !isSelected;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: v,
                        width: 14,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                        color: isSelected
                            ? _StatsTheme.primary
                            : isPeak
                                ? _StatsTheme.primaryDark
                                : _StatsTheme.mint,
                      ),
                    ],
                  );
                }),
              ),
            ),
    );
  }
}

class _ElevationChart extends StatelessWidget {
  const _ElevationChart({
    required this.stats,
    this.emptyHint = 'Додайте записи в журнал за обраний рік',
  });

  final _YearStats stats;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final spots = stats.ascentSpots;
    if (spots.isEmpty || stats.maxAscentM <= 0) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _StatsTheme.cardBorder),
        ),
        child: Center(
          child: Text(
            spots.isEmpty ? emptyHint : 'У записах немає «набору висоти» — додайте значення в журналі',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ),
      );
    }

    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final minY = 0.0;
    final top = maxY <= 0 ? 100.0 : maxY * 1.15;
    final maxX = spots.length <= 1 ? 1.0 : (spots.length - 1).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _StatsTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Макс. набір висоти',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  '${stats.maxAscentM.round()} м',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: maxX,
                minY: minY,
                maxY: top,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: top / 4,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        if (value <= 0.01) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Старт',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          );
                        }
                        if ((value - maxX).abs() < 0.01) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Фініш',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: _StatsTheme.primaryDark,
                    barWidth: 2.5,
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _StatsTheme.primary.withValues(alpha: 0.35),
                          _StatsTheme.primary.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) {
                        final isPeak = index == stats.peakIndex && stats.maxAscentM > 0;
                        return FlDotCirclePainter(
                          radius: isPeak ? 6 : 0,
                          color: _StatsTheme.orange,
                          strokeWidth: isPeak ? 2 : 0,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (stats.maxAscentM > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                stats.peakLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _StatsTheme.orange,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecordsCard extends StatelessWidget {
  const _RecordsCard({required this.stats});

  final _YearStats stats;

  @override
  Widget build(BuildContext context) {
    final trip = stats.longestTripKm != null && stats.longestTripLabel != null
        ? '${stats.longestTripKm!.round()} км · ${stats.longestTripLabel!}'
        : '—';
    final ascent = stats.maxAscentEntryLabel ?? '—';
    final day = stats.longestDayHours != null
        ? _formatDurationHours(stats.longestDayHours!)
        : '—';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _StatsTheme.cardBorder),
      ),
      child: Column(
        children: [
          _RecordRow(left: 'Найдовший похід', right: trip),
          Divider(height: 1, color: Colors.grey.shade200),
          _RecordRow(left: 'Найбільший набір висоти', right: ascent),
          Divider(height: 1, color: Colors.grey.shade200),
          _RecordRow(left: 'Найдовший день', right: day),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.left, required this.right});

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              left,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              right,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
