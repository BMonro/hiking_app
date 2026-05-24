import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/notifications/notification_ui.dart';
import '../../../core/notifications/notifications_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(notificationsListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F2),
      appBar: AppBar(
        backgroundColor: AppTheme.toolbarBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Сповіщення',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(notificationsRepositoryProvider).markAllRead();
              ref.invalidate(notificationsListProvider);
              ref.invalidate(unreadNotificationsCountProvider);
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF5E35B1),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: const Text('Прочитати все'),
          ),
        ],
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Помилка: $e'),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_active_rounded,
                        size: 64, color: Colors.deepPurple.shade200),
                    const SizedBox(height: 16),
                    Text(
                      'Поки немає сповіщень',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Тут з’являться досягнення, заявки на походи, '
                      'рішення організатора та повідомлення в чаті.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600], height: 1.4),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(notificationsListProvider);
              ref.invalidate(unreadNotificationsCountProvider);
              await ref.read(notificationsListProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final n = items[index];
                return _NotificationTile(
                  notification: n,
                  onTap: () => _onTap(context, ref, n),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _onTap(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> n,
  ) {
    final id = n['id']?.toString();
    if (id != null) {
      ref.read(notificationsRepositoryProvider).markRead(id);
      ref.invalidate(notificationsListProvider);
      ref.invalidate(unreadNotificationsCountProvider);
    }

    final type = n['type']?.toString() ?? '';
    final payload = n['payload'];
    final tripId =
        payload is Map ? payload['trip_id']?.toString() : null;

    switch (type) {
      case 'achievement':
        context.push('/achievements');
      case 'new_message':
        if (tripId != null) {
          context.push('/trips/chat/$tripId');
        }
      case 'trip_request':
      case 'trip_approved':
      case 'trip_rejected':
        if (tripId != null) {
          context.push('/trips/detail/$tripId');
        }
      default:
        break;
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  final Map<String, dynamic> notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isRead = notification['is_read'] == true;
    final type = notification['type']?.toString() ?? '';
    final style = NotificationStyle.forType(type);
    final title = notification['title']?.toString() ?? 'Сповіщення';
    final body = notification['body']?.toString();
    final created = notification['created_at']?.toString();
    final timeLabel = _formatTime(created);

    return Material(
      color: isRead ? Colors.white : style.cardBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isRead
                  ? Colors.grey.shade200
                  : style.accent.withValues(alpha: 0.35),
              width: isRead ? 1 : 1.5,
            ),
            boxShadow: isRead
                ? null
                : [
                    BoxShadow(
                      color: style.accent.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TypeIcon(style: style, isRead: isRead),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  isRead ? FontWeight.w600 : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (timeLabel != null)
                          Text(
                            timeLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                    if (body != null && body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!isRead)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 6, left: 4),
                  decoration: BoxDecoration(
                    color: style.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: style.accent.withValues(alpha: 0.45),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  String? _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      if (now.difference(dt).inDays == 0) return '$h:$m';
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return null;
    }
  }
}

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.style, required this.isRead});

  final NotificationStyle style;
  final bool isRead;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isRead ? style.iconBg.withValues(alpha: 0.5) : style.iconBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: style.accent.withValues(alpha: isRead ? 0.2 : 0.45),
        ),
      ),
      child: Icon(style.icon, color: style.accent, size: 24),
    );
  }
}
