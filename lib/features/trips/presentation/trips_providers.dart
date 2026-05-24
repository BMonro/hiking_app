import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/trip_chat_api.dart';
import '../data/trip_messages_repository.dart';

final groupHikesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.keepAlive();
  final data = await Supabase.instance.client
      .from('trips')
      .select('''
id, title, description, status, start_date, end_date, meeting_point,
max_members, organizer_id, trip_code, route_id, created_at,
routes(id, title, difficulty, distance_km, route_type),
trip_participants(user_id, status)
''')
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});

final groupHikeFilterProvider = StateProvider<String>((ref) => 'all');
final groupHikeSearchProvider = StateProvider<String>((ref) => '');

final tripDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, tripId) async {
  final row = await Supabase.instance.client
      .from('trips')
      .select(
        'id, title, description, start_date, end_date, meeting_point, '
        'max_members, status, trip_code, organizer_id, route_id, '
        'routes(id, title, difficulty, distance_km, route_type, duration_h, ascent_m, description)',
      )
      .eq('id', tripId)
      .maybeSingle();
  if (row == null) return null;
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

  final uid = Supabase.instance.client.auth.currentUser?.id;
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

/// Підписка Realtime: оновлення списку походів, деталей, заявок і сповіщень.
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
    state = AsyncData([...current, enriched]);
  }

  Future<void> send(String tripId, String content) async {
    final enriched = await _chatApi.sendMessage(
      tripId: tripId,
      content: content,
    );
    final id = enriched['id']?.toString();
    final current = state.valueOrNull ?? [];
    if (id != null && current.any((m) => m['id']?.toString() == id)) return;
    state = AsyncData([...current, enriched]);
  }
}
