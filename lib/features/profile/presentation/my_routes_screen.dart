import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../routes/domain/route_detail.dart';
import '../../routes/domain/route_model.dart';
import '../../routes/presentation/offline_route_provider.dart';
import '../../routes/presentation/routes_provider.dart';

class MyRoutesScreen extends ConsumerStatefulWidget {
  const MyRoutesScreen({super.key});

  @override
  ConsumerState<MyRoutesScreen> createState() => _MyRoutesScreenState();
}

class _MyRoutesScreenState extends ConsumerState<MyRoutesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(offlineRoutesProvider);
    });
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1) {
      ref.invalidate(offlineRoutesProvider);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F5F2),
        elevation: 0,
        title: const Text(
          'Мої маршрути',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF2E7D32),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF2E7D32),
          tabs: const [
            Tab(text: 'Створені'),
            Tab(text: 'Офлайн'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _MyAuthoredRoutesTab(),
          _OfflineRoutesTab(),
        ],
      ),
    );
  }
}

class _MyAuthoredRoutesTab extends ConsumerWidget {
  const _MyAuthoredRoutesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routesAsync = ref.watch(myRoutesProvider);

    return routesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Помилка: $e')),
      data: (routes) {
        if (routes.isEmpty) {
          return const _EmptyState(
            icon: Icons.terrain_outlined,
            title: 'Ще немає створених маршрутів',
            subtitle: 'Додайте маршрут у каталозі, щоб він з’явився тут.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: routes.length,
          itemBuilder: (context, index) => _RouteListCard(
            route: routes[index],
            onTap: () => context.push('/routes/detail/${routes[index].id}'),
          ),
        );
      },
    );
  }
}

class _OfflineRoutesTab extends ConsumerWidget {
  const _OfflineRoutesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offlineAsync = ref.watch(offlineRoutesProvider);

    return offlineAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Помилка: $e')),
      data: (routes) {
        if (routes.isEmpty) {
          return const _EmptyState(
            icon: Icons.offline_pin,
            title: 'Немає завантажених маршрутів',
            subtitle:
                'На екрані маршруту натисніть «Завантажити для офлайн», щоб зберегти карту на пристрій.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: routes.length,
          itemBuilder: (context, index) {
            final detail = routes[index];
            return _OfflineRouteCard(
              detail: detail,
              onOpen: () => context.push('/routes/detail/${detail.route.id}'),
              onDelete: () => _deleteOfflineRoute(context, ref, detail.route.id),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteOfflineRoute(
    BuildContext context,
    WidgetRef ref,
    String routeId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Видалити офлайн-карту'),
        content: const Text(
          'Завантажені тайли та локальна копія маршруту будуть видалені з пристрою.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Скасувати'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(offlineMapServiceProvider).deleteOfflineMap(routeId);
      try {
        await ref.read(routesRepositoryProvider).removeOfflineRoute(routeId);
      } catch (_) {}
      ref
        ..invalidate(offlineRoutesProvider)
        ..invalidate(routeOfflineStatusProvider(routeId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Офлайн-карту видалено')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помилка: $e')),
      );
    }
  }
}

class _RouteListCard extends StatelessWidget {
  final RouteModel route;
  final VoidCallback onTap;

  const _RouteListCard({
    required this.route,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      route.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: route.difficultyColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: route.difficultyColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      route.difficultyLabel,
                      style: TextStyle(
                        color: route.difficultyColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.straighten, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${route.distanceKm} км',
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                  const SizedBox(width: 14),
                  Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${route.durationH.toStringAsFixed(1)} год',
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineRouteCard extends ConsumerWidget {
  final RouteDetail detail;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _OfflineRouteCard({
    required this.detail,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = detail.route;
    final sizeAsync = ref.watch(_offlineRouteSizeProvider(route.id));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      route.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.offline_pin, size: 14, color: Color(0xFF2E7D32)),
                        SizedBox(width: 4),
                        Text(
                          'Офлайн',
                          style: TextStyle(
                            color: Color(0xFF2E7D32),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.straighten, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${route.distanceKm} км',
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                  const SizedBox(width: 14),
                  Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${route.durationH.toStringAsFixed(1)} год',
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              sizeAsync.when(
                loading: () => Text(
                  'Розмір кешу: ...',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (sizeMb) => Text(
                  'Розмір кешу: ${sizeMb.toStringAsFixed(1)} МБ',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onOpen,
                      child: const Text('Відкрити'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: onDelete,
                    tooltip: 'Видалити офлайн-карту',
                    icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final _offlineRouteSizeProvider =
    FutureProvider.family<double, String>((ref, routeId) async {
  return ref.watch(offlineMapServiceProvider).cacheSizeMb(routeId);
});

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
