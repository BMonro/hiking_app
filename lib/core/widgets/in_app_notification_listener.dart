import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../notifications/notification_ui.dart';
import '../notifications/notifications_provider.dart';

class InAppNotificationListener extends ConsumerWidget {
  const InAppNotificationListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(notificationsRealtimeProvider);

    ref.listen<Map<String, dynamic>?>(pendingInAppNotificationProvider,
        (prev, next) {
      if (next == null || !context.mounted) return;

      final type = next['type']?.toString() ?? '';
      final style = NotificationStyle.forType(type);
      final title = next['title']?.toString() ?? 'Сповіщення';
      final body = next['body']?.toString();
      final id = next['id']?.toString();
      final payload = next['payload'];
      final tripId =
          payload is Map ? payload['trip_id']?.toString() : null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: style.snackBg,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: style.accent.withValues(alpha: 0.28)),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          duration: const Duration(seconds: 6),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: style.iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(style.icon, color: style.accent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: style.snackText,
                      ),
                    ),
                    if (body != null && body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: style.snackText.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Відкрити',
            textColor: style.actionLabel,
            onPressed: () => _openNotification(
              context,
              ref,
              type: type,
              tripId: tripId,
              notificationId: id,
            ),
          ),
        ),
      );

      ref.read(pendingInAppNotificationProvider.notifier).state = null;
    });

    return child;
  }

  void _openNotification(
    BuildContext context,
    WidgetRef ref, {
    required String type,
    String? tripId,
    String? notificationId,
  }) {
    if (notificationId != null) {
      ref.read(notificationsRepositoryProvider).markRead(notificationId);
      ref.invalidate(notificationsListProvider);
      ref.invalidate(unreadNotificationsCountProvider);
    }

    switch (type) {
      case 'achievement':
        context.push('/achievements');
      case 'new_message':
        if (tripId != null) {
          context.push('/trips/chat/$tripId');
        } else {
          context.go('/trips');
        }
      case 'trip_request':
      case 'trip_approved':
      case 'trip_rejected':
        if (tripId != null) {
          context.push('/trips/detail/$tripId');
        } else {
          context.go('/trips');
        }
      default:
        context.push('/notifications');
    }
  }
}
