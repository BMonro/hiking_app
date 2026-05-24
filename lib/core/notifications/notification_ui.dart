import 'package:flutter/material.dart';

class NotificationStyle {
  const NotificationStyle({
    required this.icon,
    required this.accent,
    required this.iconBg,
    required this.cardBg,
    required this.snackBg,
    required this.snackText,
    required this.actionLabel,
  });

  final IconData icon;
  final Color accent;
  final Color iconBg;
  final Color cardBg;
  final Color snackBg;
  final Color snackText;
  final Color actionLabel;

  static NotificationStyle forType(String type) {
    switch (type) {
      case 'achievement':
        return const NotificationStyle(
          icon: Icons.emoji_events_rounded,
          accent: Color(0xFFE65100),
          iconBg: Color(0xFFFFE0B2),
          cardBg: Color(0xFFFFF8E1),
          snackBg: Color(0xFFFFF3E0),
          snackText: Color(0xFFBF360C),
          actionLabel: Color(0xFFE65100),
        );
      case 'trip_request':
        return const NotificationStyle(
          icon: Icons.person_add_alt_1_rounded,
          accent: Color(0xFF1565C0),
          iconBg: Color(0xFFBBDEFB),
          cardBg: Color(0xFFE3F2FD),
          snackBg: Color(0xFFE3F2FD),
          snackText: Color(0xFF0D47A1),
          actionLabel: Color(0xFF1565C0),
        );
      case 'trip_approved':
        return const NotificationStyle(
          icon: Icons.check_circle_rounded,
          accent: Color(0xFF2E7D32),
          iconBg: Color(0xFFC8E6C9),
          cardBg: Color(0xFFE8F5E9),
          snackBg: Color(0xFFE8F5E9),
          snackText: Color(0xFF1B5E20),
          actionLabel: Color(0xFF2E7D32),
        );
      case 'trip_rejected':
        return const NotificationStyle(
          icon: Icons.info_outline_rounded,
          accent: Color(0xFF7B1FA2),
          iconBg: Color(0xFFE1BEE7),
          cardBg: Color(0xFFF3E5F5),
          snackBg: Color(0xFFF3E5F5),
          snackText: Color(0xFF4A148C),
          actionLabel: Color(0xFF7B1FA2),
        );
      case 'new_message':
        return const NotificationStyle(
          icon: Icons.chat_bubble_rounded,
          accent: Color(0xFF00838F),
          iconBg: Color(0xFFB2EBF2),
          cardBg: Color(0xFFE0F7FA),
          snackBg: Color(0xFFE0F7FA),
          snackText: Color(0xFF006064),
          actionLabel: Color(0xFF00838F),
        );
      default:
        return const NotificationStyle(
          icon: Icons.notifications_active_rounded,
          accent: Color(0xFF5E35B1),
          iconBg: Color(0xFFD1C4E9),
          cardBg: Color(0xFFEDE7F6),
          snackBg: Color(0xFFEDE7F6),
          snackText: Color(0xFF4527A0),
          actionLabel: Color(0xFF5E35B1),
        );
    }
  }
}
