import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/presentation/widgets/tappable_member_header.dart';
import 'trips_providers.dart';

/// Повна інформація про спільний похід (для перегляду будь-яким користувачем).
class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({
    super.key,
    required this.tripId,
  });

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(tripsRealtimeSyncProvider);
    final tripAsync = ref.watch(tripDetailProvider(tripId));

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F2),
      appBar: AppBar(
        backgroundColor: AppTheme.toolbarBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: tripAsync.when(
          loading: () => const Text(
            'Похід',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          error: (_, __) => const Text(
            'Похід',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          data: (trip) => Text(
            trip?['title']?.toString() ?? 'Похід',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      body: tripAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Помилка: $e')),
        data: (trip) {
          if (trip == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Похід не знайдено або немає доступу',
                  style: TextStyle(color: Colors.grey[700]),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _TripDetailBody(trip: trip);
        },
      ),
    );
  }
}

class _TripDetailBody extends ConsumerWidget {
  const _TripDetailBody({required this.trip});

  final Map<String, dynamic> trip;

  static String _dateLine(dynamic start, dynamic end) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    final s = parse(start);
    final e = parse(end);
    if (s == null) return '—';
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    if (e == null || s == e) return fmt(s);
    return '${fmt(s)} — ${fmt(e)}';
  }

  static String _difficulty(dynamic v) {
    return switch (v?.toString()) {
      'easy' => 'Легкий',
      'medium' => 'Середній',
      'hard' => 'Складний',
      _ => 'Не вказано',
    };
  }

  static String _statusUa(String? s) {
    return switch (s) {
      'open' => 'Відкрито',
      'closed' => 'Закрито',
      'completed' => 'Завершено',
      'cancelled' => 'Скасовано',
      _ => s ?? '—',
    };
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = trip['routes'] as Map<String, dynamic>?;
    final routeId = route?['id']?.toString() ?? trip['route_id']?.toString();
    final title = trip['title']?.toString() ?? 'Похід';
    final desc = (trip['description'] ?? '').toString().trim();
    final meeting = (trip['meeting_point'] ?? '').toString().trim();
    final maxM = trip['max_members'];
    final approved = trip['_approved_count'] ?? 0;
    final pending = trip['_pending_count'] ?? 0;
    final orgName = trip['_organizer_name']?.toString() ?? '—';
    final orgId = trip['organizer_id']?.toString();
    final orgAvatar = trip['_organizer_avatar_url'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _statusUa(trip['status'] as String?),
            style: TextStyle(
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _section('Загальне', [
            _row(
              'Дати',
              _dateLine(trip['start_date'], trip['end_date']),
              icon: Icons.calendar_today_outlined,
            ),
            if (orgId != null && orgId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.person_outline, size: 18, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Організатор',
                        style: TextStyle(color: Colors.grey[700], fontSize: 14),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: TappableMemberHeader(
                        userId: orgId,
                        displayName: orgName,
                        avatarUrl: orgAvatar,
                        avatarRadius: 20,
                        nameStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              _row('Організатор', orgName, icon: Icons.person_outline),
            _row(
              'Учасники',
              '$approved/${maxM ?? '—'} схвалено${pending > 0 ? ' · очікує заявок: $pending' : ''}',
              icon: Icons.groups_outlined,
            ),
            _row(
              'Код походу',
              trip['trip_code']?.toString() ?? '—',
              icon: Icons.tag_outlined,
            ),
            if (meeting.isNotEmpty)
              _row('Збір / місце старту', meeting, icon: Icons.place_outlined),
          ]),
          if (desc.isNotEmpty)
            _section('Опис', [
              Text(
                desc,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Colors.grey[800],
                ),
              ),
            ]),
          if (route != null)
            _section('Маршрут', [
              _row('Назва', route['title']?.toString() ?? '—'),
              _row('Складність', _difficulty(route['difficulty'])),
              if (route['distance_km'] != null)
                _row(
                  'Дистанція',
                  '${route['distance_km']} км',
                ),
              if (route['duration_h'] != null)
                _row(
                  'Тривалість (план)',
                  '${route['duration_h']} год',
                ),
              if (route['ascent_m'] != null)
                _row('Набір висоти', '${route['ascent_m']} м'),
              if ((route['description'] ?? '').toString().trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    route['description'].toString(),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              if (routeId != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/routes/detail/$routeId'),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Відкрити картку маршруту'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2E7D32),
                      side: const BorderSide(color: Color(0xFF2E7D32)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ]),
          if (trip['_can_chat'] == true) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final id = trip['id']?.toString();
                  if (id == null) return;
                  context.push(
                    '/trips/chat/$id?title=${Uri.encodeComponent(title)}',
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2E7D32),
                  side: const BorderSide(color: Color(0xFF2E7D32)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Чат групи'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
