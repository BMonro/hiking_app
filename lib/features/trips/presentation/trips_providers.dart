import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/domain/route_model.dart';
import '../data/trip_chat_api.dart';
import '../data/trip_messages_repository.dart';

bool tripVisibleToUser(Map<String, dynamic> trip, String? userId) {
  final status = trip['status']?.toString();
  if (status != 'cancelled') return true;
  if (userId == null) return false;
  return trip['organizer_id']?.toString() == userId;
}

final groupHikesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.keepAlive();
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser?.id;
  final data = await client
      .from('trips')
      .select('''
id, title, description, status, start_date, end_date, meeting_point,
max_members, organizer_id, trip_code, route_id, created_at,
routes(id, title, difficulty, distance_km, route_type),
trip_participants(user_id, status)
''')
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(data)
      .where((trip) => tripVisibleToUser(trip, uid))
      .toList();
});

final groupHikeSearchProvider = StateProvider<String>((ref) => '');

final tripScopeFilterProvider = StateProvider<String>((ref) => 'all');

final tripDifficultyFilterProvider = StateProvider<String>((ref) => 'all');

final tripRouteTypeFilterProvider = StateProvider<String>((ref) => 'all');

final tripSortProvider = StateProvider<String>((ref) => 'newest');

int activeTripFiltersCount({
  required String scope,
  required String difficulty,
  required String routeType,
  required String sort,
}) {
  var n = 0;
  if (scope != 'all') n++;
  if (difficulty != 'all') n++;
  if (routeType != 'all') n++;
  if (sort != 'newest') n++;
  return n;
}

List<Map<String, dynamic>> filterAndSortGroupTrips({
  required List<Map<String, dynamic>> trips,
  required String userId,
  required String search,
  required String scope,
  required String difficulty,
  required String routeType,
  required String sort,
}) {
  final q = search.trim().toLowerCase();

  final filtered = trips.where((trip) {
    final route = trip['routes'] as Map<String, dynamic>?;
    final title = (trip['title'] ?? '').toString().toLowerCase();
    final code = (trip['trip_code'] ?? '').toString().toLowerCase();
    final id = (trip['id'] ?? '').toString().toLowerCase();
    final status = (trip['status'] ?? 'open').toString();
    final isMine = trip['organizer_id']?.toString() == userId;
    final routeDifficulty = route?['difficulty']?.toString() ?? '';
    final storedRouteType =
        RouteModel.normalizeStoredRouteType(route?['route_type']);

    if (q.isNotEmpty &&
        !title.contains(q) &&
        !code.contains(q) &&
        !id.contains(q)) {
      return false;
    }

    if (scope == 'mine' && !isMine) return false;
    if (scope == 'open' && status != 'open') return false;

    if (difficulty != 'all' && routeDifficulty != difficulty) return false;

    if (routeType != 'all' && storedRouteType != routeType) return false;

    return true;
  }).toList();

  filtered.sort((a, b) {
    switch (sort) {
      case 'start_asc':
        final da = _tripStartDate(a);
        final db = _tripStartDate(b);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      case 'start_desc':
        final da = _tripStartDate(a);
        final db = _tripStartDate(b);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      case 'newest':
      default:
        final ca = _tripCreatedAt(a);
        final cb = _tripCreatedAt(b);
        if (ca == null && cb == null) return 0;
        if (ca == null) return 1;
        if (cb == null) return -1;
        return cb.compareTo(ca);
    }
  });

  return filtered;
}

DateTime? _tripStartDate(Map<String, dynamic> trip) {
  final raw = trip['start_date']?.toString();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

DateTime? _tripCreatedAt(Map<String, dynamic> trip) {
  final raw = trip['created_at']?.toString();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

final tripDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, tripId) async {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser?.id;
  final row = await client
      .from('trips')
      .select(
        'id, title, description, start_date, end_date, meeting_point, '
        'max_members, status, trip_code, organizer_id, route_id, '
        'routes(id, title, difficulty, distance_km, route_type, duration_h, ascent_m, description)',
      )
      .eq('id', tripId)
      .maybeSingle();
  if (row == null) return null;
  if (!tripVisibleToUser(row, uid)) return null;
  final orgId = row['organizer_id']?.toString();
  if (orgId != null) {
    final prof = await Supabase.instance.client
        .from('profiles')
        .select('full_name, avatar_url')
        .eq('id', orgId)
        .maybeSingle();
    final n = (prof?['full_name'] as String?)?.trim();
    row['_organizer_name'] = n != null && n.isNotEmpty ? n : 'Організатор';
    row['_organizer_avatar_url'] = prof?['avatar_url'];
  } else {
    row['_organizer_name'] = '—';
  }
  final parts = await Supabase.instance.client
      .from('trip_participants')
      .select('status')
      .eq('trip_id', tripId);
  final list = List<Map<String, dynamic>>.from(parts);
  row['_approved_count'] = list.where((p) => p['status'] == 'approved').length;
  row['_pending_count'] = list.where((p) => p['status'] == 'pending').length;

  final status = row['status']?.toString();
  if (uid != null && status != 'cancelled') {
    if (row['organizer_id']?.toString() == uid) {
      row['_can_chat'] = true;
    } else {
      final myPart = await Supabase.instance.client
          .from('trip_participants')
          .select('status')
          .eq('trip_id', tripId)
          .eq('user_id', uid)
          .maybeSingle();
      row['_can_chat'] = myPart?['status'] == 'approved';
    }
  } else {
    row['_can_chat'] = false;
  }

  return row;
});

final pendingTripRequestsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, tripId) async {
  final pending = await Supabase.instance.client
      .from('trip_participants')
      .select()
      .eq('trip_id', tripId)
      .eq('status', 'pending');
  return List<Map<String, dynamic>>.from(pending);
});

final tripsRealtimeSyncProvider = Provider<void>((ref) {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser?.id;
  if (uid == null) return;

  void onTripParticipantsChange(PostgresChangePayload payload) {
    ref.invalidate(groupHikesProvider);
    final record = payload.newRecord.isNotEmpty
        ? payload.newRecord
        : payload.oldRecord;
    final tripId = record['trip_id']?.toString();
    if (tripId != null) {
      ref.invalidate(tripDetailProvider(tripId));
      ref.invalidate(pendingTripRequestsProvider(tripId));
    }
  }

  final channel = client
      .channel('trips-sync-$uid')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'trip_participants',
        callback: onTripParticipantsChange,
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'trips',
        callback: (_) => ref.invalidate(groupHikesProvider),
      )
      .subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
  });
});

final tripMessagesProvider = AsyncNotifierProvider.family<TripMessagesNotifier,
    List<Map<String, dynamic>>, String>(
  TripMessagesNotifier.new,
);

class TripMessagesNotifier
    extends FamilyAsyncNotifier<List<Map<String, dynamic>>, String> {
  RealtimeChannel? _channel;
  final _chatApi = TripChatApi();

  @override
  Future<List<Map<String, dynamic>>> build(String tripId) async {
    ref.onDispose(() {
      final ch = _channel;
      if (ch != null) {
        Supabase.instance.client.removeChannel(ch);
      }
    });
    _subscribe(tripId);
    return _chatApi.listMessages(tripId);
  }

  void _subscribe(String tripId) {
    final client = Supabase.instance.client;
    _channel = client
        .channel('trip-chat-$tripId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'trip_id',
            value: tripId,
          ),
          callback: (payload) => _onInsert(payload.newRecord),
        )
        .subscribe();
  }

  Future<void> _onInsert(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    final current = state.valueOrNull ?? [];
    if (id != null && current.any((m) => m['id']?.toString() == id)) return;
    final enriched = await enrichTripMessageRow(row);
    final updated = [...current, enriched];
    attachReplyPreviews(updated);
    state = AsyncData(updated);
  }

  Future<void> send(
    String tripId,
    String content, {
    String? replyToId,
  }) async {
    final enriched = await _chatApi.sendMessage(
      tripId: tripId,
      content: content,
      replyToId: replyToId,
    );
    final id = enriched['id']?.toString();
    final current = state.valueOrNull ?? [];
    if (id != null && current.any((m) => m['id']?.toString() == id)) return;
    final updated = [...current, enriched];
    attachReplyPreviews(updated);
    state = AsyncData(updated);
  }
}
