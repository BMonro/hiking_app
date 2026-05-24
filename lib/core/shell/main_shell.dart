import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/in_app_notification_listener.dart';
import '../../features/trips/presentation/trips_providers.dart';

class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(tripsRealtimeSyncProvider);

    return InAppNotificationListener(
      child: Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFD8E0D8), width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Головна',
                  path: '/home',
                  context: context,
                ),
                _NavItem(
                  icon: Icons.terrain_outlined,
                  activeIcon: Icons.terrain,
                  label: 'Маршрути',
                  path: '/routes',
                  context: context,
                ),
                _NavItem(
                  icon: Icons.map_outlined,
                  activeIcon: Icons.map,
                  label: 'Карта',
                  path: '/navigation',
                  context: context,
                  isCentral: true,
                ),
                _NavItem(
                  icon: Icons.card_travel_outlined,
                  activeIcon: Icons.card_travel,
                  label: 'Групи',
                  path: '/trips',
                  context: context,
                ),
                _NavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: 'Профіль',
                  path: '/profile',
                  context: context,
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String path;
  final BuildContext context;
  final bool isCentral;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.path,
    required this.context,
    this.isCentral = false,
  });

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final isActive = location.startsWith(path);

    if (isCentral) {
      return GestureDetector(
        onTap: () => this.context.go(path),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF2E7D32) : const Color(0xFFF0F0E8),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isActive ? activeIcon : icon,
            color: isActive ? Colors.white : Colors.grey[600],
            size: 22,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => this.context.go(path),
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? const Color(0xFF2E7D32) : Colors.grey[500],
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isActive ? const Color(0xFF2E7D32) : Colors.grey[500],
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
