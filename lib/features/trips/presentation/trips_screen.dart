import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/domain/route_model.dart';

String _formatTripDateRange(Map<String, dynamic>? trip) {
  if (trip == null) return '';
  final s = trip['start_date'];
  final e = trip['end_date'];
  if (s == null) return '';
  final sd = s.toString().split('T').first;
  final ed = e?.toString().split('T').first;
  if (ed == null || ed == sd) return sd;
  return '$sd — $ed';
}

String _fitnessLevelUa(String? v) {
  return switch (v) {
    'beginner' => 'Початківець',
    'intermediate' => 'Середній',
    'advanced' => 'Експерт',
    _ => 'Не вказано',
  };
}

String _profileDisplayName(Map<String, dynamic>? prof) {
  if (prof == null) return 'Учасник';
  final n = (prof['full_name'] as String?)?.trim();
  return n != null && n.isNotEmpty ? n : 'Учасник';
}

final groupHikesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await Supabase.instance.client
      .from('trips')
      .select('*, routes(id, title, difficulty, distance_km, route_type), trip_participants(user_id, status)')
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});

final groupHikeFilterProvider = StateProvider<String>((ref) => 'all');
final groupHikeSearchProvider = StateProvider<String>((ref) => '');

class GroupHikesScreen extends ConsumerWidget {
  const GroupHikesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(groupHikesProvider);
    final filter = ref.watch(groupHikeFilterProvider);
    final search = ref.watch(groupHikeSearchProvider).trim().toLowerCase();
    final userId = Supabase.instance.client.auth.currentUser!.id;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F5F2),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Групові походи',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Спільні походи',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showUpsertTripDialog(context, ref),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Створити похід'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              onChanged: (value) =>
                  ref.read(groupHikeSearchProvider.notifier).state = value,
              decoration: InputDecoration(
                hintText: 'Пошук за назвою, ID або кодом',
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
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _FilterPill(
                  label: 'Всі',
                  value: 'all',
                  selected: filter == 'all',
                ),
                const SizedBox(width: 8),
                _FilterPill(
                  label: 'Мої',
                  value: 'mine',
                  selected: filter == 'mine',
                ),
                const SizedBox(width: 8),
                _FilterPill(
                  label: 'Відкриті',
                  value: 'open',
                  selected: filter == 'open',
                ),
                const SizedBox(width: 8),
                _FilterPill(
                  label: 'Легкі',
                  value: 'easy',
                  selected: filter == 'easy',
                ),
                const SizedBox(width: 8),
                _FilterPill(
                  label: 'Середні',
                  value: 'medium',
                  selected: filter == 'medium',
                ),
                const SizedBox(width: 8),
                _FilterPill(
                  label: 'Складні',
                  value: 'hard',
                  selected: filter == 'hard',
                ),
                const SizedBox(width: 8),
                _FilterPill(
                  label: 'Кільцеві',
                  value: 'circular',
                  selected: filter == 'circular',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: tripsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Помилка: $e')),
              data: (trips) {
                final filtered = trips.where((trip) {
                  final route = trip['routes'] as Map<String, dynamic>?;
                  final title = (trip['title'] ?? '').toString().toLowerCase();
                  final code = (trip['trip_code'] ?? '').toString().toLowerCase();
                  final id = (trip['id'] ?? '').toString().toLowerCase();
                  final status = (trip['status'] ?? 'open').toString();
                  final isMine = trip['organizer_id'] == userId;
                  final difficulty = route?['difficulty']?.toString();
                  final isEasy = difficulty == 'easy';
                  final isMedium = difficulty == 'medium';
                  final isHard = difficulty == 'hard';
                  final routeType =
                      RouteModel.normalizeStoredRouteType(route?['route_type']);
                  final isCircular = routeType == 'circular';
                  final matchesSearch = search.isEmpty ||
                      title.contains(search) ||
                      code.contains(search) ||
                      id.contains(search);

                  final matchesFilter = switch (filter) {
                    'mine' => isMine,
                    'easy' => isEasy,
                    'medium' => isMedium,
                    'hard' => isHard,
                    'circular' => isCircular,
                    'open' => status == 'open',
                    _ => true,
                  };

                  return matchesSearch && matchesFilter;
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text('Нічого не знайдено за поточними фільтрами'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _TripCard(
                    trip: filtered[index],
                    onRefresh: () => ref.invalidate(groupHikesProvider),
                    onEdit: () => _showUpsertTripDialog(
                      context,
                      ref,
                      existingTrip: filtered[index],
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

  Future<void> _showUpsertTripDialog(
    BuildContext context,
    WidgetRef ref, {
    Map<String, dynamic>? existingTrip,
  }) async {
    final editingTrip = existingTrip;
    final isEditing = editingTrip != null;
    final titleController =
        TextEditingController(text: existingTrip?['title']?.toString() ?? '');
    final descController =
        TextEditingController(text: existingTrip?['description']?.toString() ?? '');
    final meetingController = TextEditingController(
      text: existingTrip?['meeting_point']?.toString() ?? '',
    );
    final maxMembersController = TextEditingController(
      text: (existingTrip?['max_members'] ?? 10).toString(),
    );

    DateTime? startDate = isEditing ? DateTime.parse(editingTrip['start_date']) : null;
    DateTime? endDate = isEditing ? DateTime.parse(editingTrip['end_date']) : null;
    String? selectedRouteId = editingTrip?['route_id']?.toString();

    final routes = await Supabase.instance.client
        .from('routes')
        .select('id, title, difficulty, distance_km, route_type, route_points(name, point_type)')
        .eq('is_public', true)
        .order('created_at', ascending: false);
    final routeList = List<Map<String, dynamic>>.from(routes);

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final selectedRoute = routeList.where((r) => r['id'].toString() == selectedRouteId).firstOrNull;
          final points = selectedRoute?['route_points'] as List<dynamic>? ?? [];
          final peakNames = points
              .whereType<Map>()
              .where((p) => p['point_type'] == 'peak')
              .map((p) => p['name']?.toString() ?? 'Вершина')
              .take(4)
              .toList();
          final waypointNames = points
              .whereType<Map>()
              .where((p) => p['point_type'] != 'peak')
              .map((p) => p['name']?.toString() ?? 'Точка')
              .take(6)
              .toList();

          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isEditing ? 'Редагувати похід' : 'Створити похід',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: ValueKey(selectedRouteId ?? 'route'),
                    initialValue: selectedRouteId,
                    decoration: _inputDecoration('Маршрут *'),
                    items: routeList
                        .map(
                          (route) => DropdownMenuItem<String>(
                            value: route['id'].toString(),
                            child: Text(route['title']?.toString() ?? 'Маршрут'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setModalState(() => selectedRouteId = value),
                  ),
                  const SizedBox(height: 12),
                  if (selectedRoute != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF4EA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Складність: ${_difficultyLabel(selectedRoute['difficulty'])}'),
                          Text(
                            'Вид маршруту: ${RouteModel.labelUkForRouteType(RouteModel.normalizeStoredRouteType(selectedRoute['route_type']))}',
                          ),
                          Text('Дистанція: ${selectedRoute['distance_km'] ?? '-'} км'),
                          if (peakNames.isNotEmpty) Text('Вершини: ${peakNames.join(', ')}'),
                          if (waypointNames.isNotEmpty)
                            Text('Точки: ${waypointNames.join(', ')}'),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: _inputDecoration('Назва походу *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    maxLines: 3,
                    decoration: _inputDecoration('Опис *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: meetingController,
                    decoration: _inputDecoration('Місце відправлення / збору *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: maxMembersController,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration('Кількість осіб *'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: startDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setModalState(() => startDate = picked);
                            }
                          },
                          child: Text(
                            startDate == null
                                ? 'Дата початку *'
                                : _dateLabel(startDate!),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: endDate ?? (startDate ?? DateTime.now()),
                              firstDate: startDate ?? DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setModalState(() => endDate = picked);
                            }
                          },
                          child: Text(
                            endDate == null
                                ? 'Дата завершення *'
                                : _dateLabel(endDate!),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final errors = <String>[];
                      final maxMembers = int.tryParse(maxMembersController.text.trim());
                      if (selectedRouteId == null) errors.add('Оберіть маршрут');
                      if (titleController.text.trim().isEmpty) errors.add('Введіть назву');
                      if (descController.text.trim().isEmpty) errors.add('Додайте опис');
                      if (meetingController.text.trim().isEmpty) {
                        errors.add('Вкажіть місце збору');
                      }
                      if (startDate == null || endDate == null) {
                        errors.add('Вкажіть дати походу');
                      } else if (endDate!.isBefore(startDate!)) {
                        errors.add('Дата завершення не може бути раніше початку');
                      }
                      if (maxMembers == null || maxMembers < 2) {
                        errors.add('Кількість осіб має бути не менше 2');
                      }

                      if (errors.isNotEmpty) {
                        if (!context.mounted) return;
                        await showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Перевірте дані'),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: errors
                                    .map(
                                      (e) => Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Text('• $e'),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                        return;
                      }

                      try {
                        final userId = Supabase.instance.client.auth.currentUser!.id;
                        final payload = <String, dynamic>{
                          'title': titleController.text.trim(),
                          'description': descController.text.trim(),
                          'meeting_point': meetingController.text.trim(),
                          'max_members': maxMembers,
                          'start_date': startDate!.toIso8601String().split('T')[0],
                          'end_date': endDate!.toIso8601String().split('T')[0],
                          'route_id': selectedRouteId,
                        };

                        if (isEditing) {
                          await Supabase.instance.client
                              .from('trips')
                              .update(payload)
                              .eq('id', editingTrip['id']);
                        } else {
                          final code = 'TRIP-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
                          final inserted = await Supabase.instance.client
                              .from('trips')
                              .insert({
                                ...payload,
                                'organizer_id': userId,
                                'status': 'open',
                                'trip_code': code,
                              })
                              .select('id')
                              .single();

                          await Supabase.instance.client.from('trip_participants').upsert({
                            'trip_id': inserted['id'],
                            'user_id': userId,
                            'status': 'approved',
                          });
                        }

                        ref.invalidate(groupHikesProvider);
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Помилка: $e')),
                          );
                        }
                      }
                    },
                    child: Text(isEditing ? 'Зберегти зміни' : 'Опублікувати'),
                  ),
                ],
              ),
            ),
          );
        },
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

  static String _difficultyLabel(dynamic value) {
    switch (value) {
      case 'easy':
        return 'Легкий';
      case 'medium':
        return 'Середній';
      case 'hard':
        return 'Складний';
      default:
        return 'Не вказано';
    }
  }

  static String _dateLabel(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
  }
}

class _FilterPill extends ConsumerWidget {
  final String label;
  final String value;
  final bool selected;

  const _FilterPill({
    required this.label,
    required this.value,
    required this.selected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => ref.read(groupHikeFilterProvider.notifier).state = value,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            color: selected ? Colors.white : Colors.grey[700],
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final VoidCallback onRefresh;
  final VoidCallback onEdit;

  const _TripCard({
    required this.trip,
    required this.onRefresh,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final startDate = DateTime.parse(trip['start_date']);
    final endDate = DateTime.parse(trip['end_date']);
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final isOrganizer = trip['organizer_id'] == userId;
    final status = trip['status'] as String? ?? 'open';
    final maxMembers = trip['max_members'] as int? ?? 0;
    final participants =
        (trip['trip_participants'] as List<dynamic>? ?? []).whereType<Map>().toList();
    final approvedCount = participants.where((p) => p['status'] == 'approved').length;
    final pendingCount = participants.where((p) => p['status'] == 'pending').length;
    final myRequest = participants.cast<Map?>().firstWhere(
          (p) => p?['user_id'] == userId,
          orElse: () => null,
        );
    final myRequestStatus = myRequest?['status']?.toString();
    final route = trip['routes'] as Map<String, dynamic>?;

    final statusInfo = _statusInfo(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    trip['title']?.toString() ?? '',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusInfo.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusInfo.color.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    statusInfo.label,
                    style: TextStyle(
                      color: statusInfo.color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_dateLabel(startDate)} - ${_dateLabel(endDate)}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Код: ${trip['trip_code'] ?? '-'} · ID: ${trip['id'].toString().substring(0, 8)}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            if (route != null) ...[
              const SizedBox(height: 6),
              Text(
                'Маршрут: ${route['title'] ?? '—'} · ${_difficultyLabel(route['difficulty'])}',
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
            ],
            if ((trip['meeting_point'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Місце відправлення: ${trip['meeting_point']}',
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
            ],
            if ((trip['description'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                trip['description'].toString(),
                style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.35),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push('/trips/detail/${trip['id']}'),
                icon: const Icon(Icons.info_outline, size: 20),
                label: const Text('Деталі походу'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2E7D32),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.groups, size: 18, color: Color(0xFF2E7D32)),
                const SizedBox(width: 6),
                Text(
                  '$approvedCount/$maxMembers',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (pendingCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Очікують: $pendingCount'),
                  ),
                ],
                const Spacer(),
                if (isOrganizer) ...[
                  IconButton(
                    tooltip: 'Редагувати',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Скасувати похід',
                    onPressed: status == 'open'
                        ? () => _cancelTrip(context, trip['id'].toString())
                        : null,
                    icon: const Icon(Icons.cancel_outlined),
                  ),
                  IconButton(
                    tooltip: 'Керування заявками',
                    onPressed: () => _showManageRequests(context, trip['id'].toString()),
                    icon: const Icon(Icons.manage_accounts_outlined),
                  ),
                ] else ...[
                  _buildJoinAction(
                    context,
                    status: status,
                    myRequestStatus: myRequestStatus,
                    tripId: trip['id'].toString(),
                    organizerId: trip['organizer_id'].toString(),
                    approvedCount: approvedCount,
                    maxMembers: maxMembers,
                  ),
                ],
              ],
            ),
            if (status != 'cancelled' &&
                (isOrganizer || myRequestStatus == 'approved')) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    final title = trip['title']?.toString() ?? 'Похід';
                    context.push(
                      '/trips/chat/${trip['id']}?title=${Uri.encodeComponent(title)}',
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2E7D32),
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  label: const Text('Чат групи'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildJoinAction(
    BuildContext context, {
    required String status,
    required String? myRequestStatus,
    required String tripId,
    required String organizerId,
    required int approvedCount,
    required int maxMembers,
  }) {
    if (status != 'open') {
      return Text('Набір закрито', style: TextStyle(color: Colors.grey[600]));
    }

    if (myRequestStatus == 'approved') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('Ви в групі'),
      );
    }

    if (myRequestStatus == 'pending') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('Запит на розгляді'),
      );
    }

    return ElevatedButton(
      onPressed: () => _joinTrip(
        context,
        tripId,
        organizerId,
        approvedCount: approvedCount,
        maxMembers: maxMembers,
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      child: const Text('Подати запит'),
    );
  }

  Future<void> _joinTrip(
    BuildContext context,
    String tripId,
    String organizerId, {
    required int approvedCount,
    required int maxMembers,
  }) async {
    if (approvedCount >= maxMembers) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Група вже набрана за кількістю місць')),
        );
      }
      return;
    }
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client.from('trip_participants').upsert({
        'trip_id': tripId,
        'user_id': userId,
        'status': 'pending',
      });

      try {
        final tripRow = await Supabase.instance.client
            .from('trips')
            .select('title, start_date, end_date')
            .eq('id', tripId)
            .maybeSingle();
        final me = await Supabase.instance.client
            .from('profiles')
            .select('full_name, age, fitness_level, bio')
            .eq('id', userId)
            .maybeSingle();
        final applicantName = (me?['full_name'] as String?)?.trim();
        final name =
            applicantName != null && applicantName.isNotEmpty
                ? applicantName
                : 'Учасник';
        final tripTitle = (tripRow?['title'] as String?)?.trim() ?? 'Похід';
        final dates = _formatTripDateRange(tripRow);
        final age = me?['age'];
        final fit = _fitnessLevelUa(me?['fitness_level'] as String?);
        final bio = (me?['bio'] as String?)?.trim() ?? '';
        final bioShort =
            bio.length > 120 ? '${bio.substring(0, 120)}…' : bio;

        final detailLines = <String>[
          'Похід: $tripTitle',
          if (dates.isNotEmpty) 'Дати: $dates',
          if (age != null) 'Вік: $age',
          'Рівень: $fit',
          if (bioShort.isNotEmpty) 'Про себе: $bioShort',
        ];

        await Supabase.instance.client.from('notifications').insert({
          'user_id': organizerId,
          'type': 'trip_request',
          'title': 'Заявка від $name',
          'body': detailLines.join('\n'),
          'payload': {
            'trip_id': tripId,
            'applicant_id': userId,
            'applicant_name': name,
            'trip_title': tripTitle,
          },
        });
      } catch (_) {
        // RLS на notifications може відхилити вставку — заявка вже збережена
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Запит надіслано організатору')),
        );
      }
      onRefresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Помилка: $e')),
        );
      }
    }
  }

  Future<void> _cancelTrip(BuildContext context, String tripId) async {
    try {
      await Supabase.instance.client
          .from('trips')
          .update({'status': 'cancelled'})
          .eq('id', tripId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Похід скасовано')),
        );
      }
      onRefresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Помилка скасування: $e')),
        );
      }
    }
  }

  Future<void> _showManageRequests(BuildContext context, String tripId) async {
    final pending = await Supabase.instance.client
        .from('trip_participants')
        .select()
        .eq('trip_id', tripId)
        .eq('status', 'pending');
    final pendingList = List<Map<String, dynamic>>.from(pending);
    final applicantIds = pendingList
        .map((p) => p['user_id']?.toString())
        .whereType<String>()
        .toList();
    final profileById = <String, Map<String, dynamic>>{};
    if (applicantIds.isNotEmpty) {
      final profs = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, age, fitness_level, bio')
          .inFilter('id', applicantIds);
      for (final p in List<Map<String, dynamic>>.from(profs)) {
        final id = p['id']?.toString();
        if (id == null) continue;
        profileById[id] = p;
      }
    }

    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) {
        if (pendingList.isEmpty) {
          return const SizedBox(
            height: 140,
            child: Center(child: Text('Немає запитів у черзі')),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: pendingList.length,
          itemBuilder: (context, index) {
            final request = pendingList[index];
            final applicantId = request['user_id'].toString();
            final prof = profileById[applicantId];
            final displayName = _profileDisplayName(prof);
            final age = prof?['age'];
            final fit = _fitnessLevelUa(prof?['fitness_level'] as String?);
            final bio = (prof?['bio'] as String?)?.trim() ?? '';
            return Card(
              child: ListTile(
                isThreeLine: bio.isNotEmpty,
                title: Text(
                  displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        if (age != null) 'Вік: $age',
                        'Підготовка: $fit',
                      ].join(' · '),
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        bio,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => _resolveRequest(
                        context,
                        tripId: tripId,
                        applicantId: applicantId,
                        approved: false,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check, color: Color(0xFF2E7D32)),
                      onPressed: () => _resolveRequest(
                        context,
                        tripId: tripId,
                        applicantId: applicantId,
                        approved: true,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _resolveRequest(
    BuildContext context, {
    required String tripId,
    required String applicantId,
    required bool approved,
  }) async {
    try {
      if (approved) {
        final tripRow = await Supabase.instance.client
            .from('trips')
            .select('max_members')
            .eq('id', tripId)
            .maybeSingle();
        final maxM = (tripRow?['max_members'] as num?)?.toInt() ?? 0;
        final parts = await Supabase.instance.client
            .from('trip_participants')
            .select('status')
            .eq('trip_id', tripId);
        final approvedN = List<Map<String, dynamic>>.from(parts)
            .where((p) => p['status'] == 'approved')
            .length;
        if (approvedN >= maxM) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Досягнуто максимум учасників — спочатку звільніть місце'),
              ),
            );
          }
          return;
        }
      }

      final status = approved ? 'approved' : 'rejected';
      await Supabase.instance.client
          .from('trip_participants')
          .update({'status': status})
          .eq('trip_id', tripId)
          .eq('user_id', applicantId);

      try {
        final tripRow = await Supabase.instance.client
            .from('trips')
            .select('title, organizer_id')
            .eq('id', tripId)
            .maybeSingle();
        final tripTitle =
            (tripRow?['title'] as String?)?.trim() ?? 'Похід';
        final orgId = tripRow?['organizer_id']?.toString();
        String organizerLabel = 'Організатор';
        if (orgId != null) {
          final orgProf = await Supabase.instance.client
              .from('profiles')
              .select('full_name')
              .eq('id', orgId)
              .maybeSingle();
          final on = (orgProf?['full_name'] as String?)?.trim();
          if (on != null && on.isNotEmpty) organizerLabel = on;
        }

        await Supabase.instance.client.from('notifications').insert({
          'user_id': applicantId,
          'type': approved ? 'trip_approved' : 'trip_rejected',
          'title': approved
              ? 'Вас схвалено: $tripTitle'
              : 'Заявку відхилено: $tripTitle',
          'body': approved
              ? 'Організатор $organizerLabel додав вас до походу «$tripTitle». Відкрийте чат групи для спілкування.'
              : 'Організатор $organizerLabel відхилив запит на похід «$tripTitle».',
          'payload': {
            'trip_id': tripId,
            'organizer_name': organizerLabel,
            'trip_title': tripTitle,
          },
        });
      } catch (_) {}

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approved ? 'Учасника додано' : 'Запит відхилено')),
        );
      }
      onRefresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Помилка обробки запиту: $e')),
        );
      }
    }
  }

  static _TripStatusInfo _statusInfo(String status) {
    return switch (status) {
      'open' => _TripStatusInfo('Відкрито', const Color(0xFF2E7D32)),
      'closed' => _TripStatusInfo('Закрито', Colors.orange),
      'completed' => _TripStatusInfo('Завершено', Colors.grey),
      'cancelled' => _TripStatusInfo('Скасовано', Colors.redAccent),
      _ => _TripStatusInfo(status, Colors.grey),
    };
  }

  static String _difficultyLabel(dynamic value) {
    return switch (value) {
      'easy' => 'Легкий',
      'medium' => 'Середній',
      'hard' => 'Складний',
      _ => 'Невідомо',
    };
  }

  static String _dateLabel(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
  }
}

class _TripStatusInfo {
  final String label;
  final Color color;

  const _TripStatusInfo(this.label, this.color);
}

extension _FirstWhereOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
