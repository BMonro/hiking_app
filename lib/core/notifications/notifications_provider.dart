import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/trips/presentation/trips_providers.dart';
import 'notification_preferences_provider.dart';
import 'notifications_repository.dart';

final notificationsRepositoryProvider =
    Provider((ref) => NotificationsRepository());

final notificationsListProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.read(notificationsRepositoryProvider).fetch();
});

final unreadNotificationsCountProvider = FutureProvider<int>((ref) async {
  return ref.read(notificationsRepositoryProvider).unreadCount();
});

final pendingInAppNotificationProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);

final notificationsRealtimeProvider = Provider<void>((ref) {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser?.id;
  if (uid == null) return;

  void invalidateAll() {
    ref.invalidate(notificationsListProvider);
    ref.invalidate(unreadNotificationsCountProvider);
  }

  void onNotificationInsert(PostgresChangePayload payload) {
    final record = Map<String, dynamic>.from(payload.newRecord);
    final type = record['type']?.toString() ?? '';
    final prefs = ref.read(notificationPreferencesProvider);

    invalidateAll();

    if (!prefs.allowsInAppType(type)) return;

    final payloadMap = record['payload'];
    final tripId = payloadMap is Map
        ? payloadMap['trip_id']?.toString()
        : null;

    if (type == 'new_message' && tripId != null) {
      ref.invalidate(tripMessagesProvider(tripId));
    }

    if (type == 'trip_request' ||
        type == 'trip_approved' ||
        type == 'trip_rejected') {
      ref.invalidate(groupHikesProvider);
      if (tripId != null) {
        ref.invalidate(tripDetailProvider(tripId));
        ref.invalidate(pendingTripRequestsProvider(tripId));
      }
    }

    ref.read(pendingInAppNotificationProvider.notifier).state = record;
  }

  final channel = client
      .channel('notifications-sync-$uid')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: uid,
        ),
        callback: onNotificationInsert,
      )
      .subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
  });
});
