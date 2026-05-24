import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/network_status_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/offline_only_message.dart';
import '../domain/route_detail.dart';
import '../domain/route_model.dart';
import '../domain/route_rating.dart';
import '../../navigation/data/offline_route_path_resolver.dart';
import '../../navigation/data/routing_repository.dart';
import 'offline_route_provider.dart';
import 'routes_provider.dart';
import 'routes_screen.dart' show RouteEditorScreen;
import 'widgets/route_reviews_section.dart'
    show RouteReviewsPreviewTile, StarRatingDisplay;

class RouteDetailsScreen extends ConsumerWidget {
  final String routeId;

  const RouteDetailsScreen({
    super.key,
    required this.routeId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(routeDetailProvider(routeId));

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F2),
      appBar: AppBar(
        backgroundColor: AppTheme.toolbarBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: detailAsync.when(
          loading: () => const Text(
            'Маршрут',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          error: (_, __) => const Text(
            'Маршрут',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          data: (detail) => Text(
            detail?.route.title ?? 'Маршрут',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Помилка: $e'),
          ),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Маршрут не знайдено'));
          }
          return _RouteDetailBody(detail: detail, routeId: routeId, ref: ref);
        },
      ),
    );
  }
}

class _RouteDetailBody extends StatelessWidget {
  final RouteDetail detail;
  final String routeId;
  final WidgetRef ref;

  const _RouteDetailBody({
    required this.detail,
    required this.routeId,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final hasNetwork = ref.watch(hasNetworkProvider).value ?? true;
    final route = detail.route;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isAuthor =
        currentUserId != null && route.authorId == currentUserId;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: route.difficultyColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: route.difficultyColor.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                route.difficultyLabel,
                style: TextStyle(
                  color: route.difficultyColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.alt_route, size: 18, color: Colors.grey[700]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Вид: ${route.routeTypeLabelUk}',
                  style: TextStyle(color: Colors.grey[700], fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _RouteRatingChip(routeId: routeId),
          const SizedBox(height: 20),
          const Text(
            'Огляд',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _StatsRow(route: route),
          const SizedBox(height: 24),
          const Text(
            'Точки маршруту',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (detail.waypoints.isEmpty)
            Text(
              'Точки ще не додані.',
              style: TextStyle(color: Colors.grey[600]),
            )
          else
            ...detail.waypoints.map(
              (w) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                    child: Icon(
                      _iconForPointType(w.pointType),
                      color: const Color(0xFF2E7D32),
                      size: 20,
                    ),
                  ),
                  title: Text(
                    (w.name != null && w.name!.isNotEmpty)
                        ? w.name!
                        : w.typeLabelUk,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${w.typeLabelUk} · '
                    '${w.position.latitude.toStringAsFixed(4)}, '
                    '${w.position.longitude.toStringAsFixed(4)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ),
            ),
          if (route.description.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Опис',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                route.description,
                style: const TextStyle(fontSize: 14, height: 1.45),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Рейтинг та відгуки',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          RouteReviewsPreviewTile(
            routeId: routeId,
            authorId: route.authorId,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: hasNetwork
                  ? () => context.push('/routes/detail/$routeId/weather')
                  : () => showWeatherOfflineSnackBar(context),
              icon: Icon(
                Icons.wb_cloudy_outlined,
                color: hasNetwork ? const Color(0xFF1565C0) : Colors.grey,
              ),
              label: Text(
                hasNetwork
                    ? 'Погода на точках маршруту'
                    : 'Погода (потрібен інтернет)',
                style: TextStyle(color: hasNetwork ? null : Colors.grey[600]),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(
                  color: hasNetwork ? const Color(0xFF1565C0) : Colors.grey.shade400,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _OfflineDownloadButton(detail: detail, routeId: routeId),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final hasOffline = await ref
                    .read(offlineMapServiceProvider)
                    .hasOfflineMap(routeId);
                final offlineQ = hasOffline ? '&offline=true' : '';
                if (!context.mounted) return;
                context.push(
                  '/navigation?routeId=${Uri.encodeComponent(routeId)}$offlineQ',
                );
              },
              icon: const Icon(Icons.map_outlined),
              label: const Text('Почати проходження'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (isAuthor) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => RouteEditorScreen(route: route),
                        ),
                      );
                    },
                    child: const Text('Редагувати'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Видалити маршрут'),
                          content: Text('Видалити «${route.title}»?'),
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
                      if (ok == true && context.mounted) {
                        try {
                          await ref
                              .read(routesRepositoryProvider)
                              .deleteRoute(routeId);
                          ref
                            ..invalidate(routesProvider)
                            ..invalidate(displayedRoutesProvider)
                            ..invalidate(myPublicRoutesProvider)
                            ..invalidate(myPrivateRoutesProvider)
                            ..invalidate(routeDetailProvider(routeId));
                          if (context.mounted) context.pop();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Помилка: $e')),
                            );
                          }
                        }
                      }
                    },
                    child: const Text('Видалити'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconForPointType(String t) {
    return _RouteDetailWaypointIcons.iconForPointType(t);
  }
}

class _OfflineDownloadButton extends ConsumerStatefulWidget {
  final RouteDetail detail;
  final String routeId;

  const _OfflineDownloadButton({
    required this.detail,
    required this.routeId,
  });

  @override
  ConsumerState<_OfflineDownloadButton> createState() =>
      _OfflineDownloadButtonState();
}

class _OfflineDownloadButtonState extends ConsumerState<_OfflineDownloadButton> {
  bool _downloading = false;
  double _progress = 0;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
    });

    final offlineService = ref.read(offlineMapServiceProvider);
    final routesRepo = ref.read(routesRepositoryProvider);
    final routingRepo = RoutingRepository();

    try {
      final pathPolyline =
          await resolveRoutePathPolyline(widget.detail, routingRepo);

      await for (final progress in offlineService.downloadRouteMap(
        widget.detail,
        pathPolyline: pathPolyline,
      )) {
        if (!mounted) return;
        setState(() => _progress = progress.fraction);
      }

      final sizeMb = await offlineService.cacheSizeMb(widget.routeId);
      try {
        await routesRepo.saveOfflineRoute(widget.routeId, sizeMb);
      } catch (_) {

      }

      ref
        ..invalidate(routeOfflineStatusProvider(widget.routeId))
        ..invalidate(offlineMapsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Офлайн-пакет збережено: карта та лінія маршруту',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не вдалося завантажити карту: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _progress = 0;
        });
      }
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Видалити офлайн-карту'),
        content: const Text(
          'З пристрою буде видалено завантажену карту та збережений шлях. Маршрут у каталозі залишиться.',
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
    if (ok != true || !mounted) return;

    setState(() => _downloading = true);
    try {
      await ref.read(offlineMapServiceProvider).deleteOfflineMap(widget.routeId);
      try {
        await ref.read(routesRepositoryProvider).removeOfflineRoute(widget.routeId);
      } catch (_) {}
      ref
        ..invalidate(routeOfflineStatusProvider(widget.routeId))
        ..invalidate(offlineMapsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Офлайн-карту видалено')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помилка: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final offlineAsync = ref.watch(routeOfflineStatusProvider(widget.routeId));

    return offlineAsync.when(
      loading: () => const SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: null,
          child: Text('Перевірка офлайн-карти...'),
        ),
      ),
      error: (_, __) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _downloading ? null : _download,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Завантажити карту офлайн'),
        ),
      ),
      data: (isOffline) {
        if (_downloading) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFF2E7D32),
              ),
              const SizedBox(height: 8),
              Text(
                _progress > 0
                    ? 'Завантаження карти ${(_progress * 100).round()}%'
                    : 'Підготовка завантаження...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
            ],
          );
        }

        if (isOffline) {
          return SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _remove,
              icon: const Icon(Icons.offline_pin),
              label: const Text('Офлайн-карта збережена'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2E7D32),
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Color(0xFF2E7D32)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          );
        }

        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Завантажити карту офлайн'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF37474F),
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: Colors.grey.shade400),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RouteRatingChip extends ConsumerWidget {
  final String routeId;

  const _RouteRatingChip({required this.routeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(routeReviewsProvider(routeId));
    return reviewsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (summary) {
        if (summary.count == 0) return const SizedBox.shrink();
        return Row(
          children: [
            StarRatingDisplay(
              rating: summary.averageRating ?? 0,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              '${summary.averageLabel} · '
              '${RouteReviewsSummary.reviewsCountLabel(summary.count)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RouteDetailWaypointIcons {
  static IconData iconForPointType(String t) {
    return switch (t) {
      'peak' => Icons.terrain,
      'water' => Icons.water_drop_outlined,
      'shelter' => Icons.night_shelter_outlined,
      'danger' => Icons.warning_amber_outlined,
      'viewpoint' => Icons.photo_camera_outlined,
      'finish' => Icons.flag,
      'start' => Icons.play_circle_outline,
      _ => Icons.place_outlined,
    };
  }
}

class _StatsRow extends StatelessWidget {
  final RouteModel route;

  const _StatsRow({required this.route});

  @override
  Widget build(BuildContext context) {
    final pace = route.durationH > 0
        ? '${(route.distanceKm / route.durationH).toStringAsFixed(1)} км/год'
        : '—';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.straighten,
                label: 'Відстань',
                value: '${route.distanceKm} км',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.schedule,
                label: 'Час',
                value: '${route.durationH.toStringAsFixed(1)} год',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.trending_up,
                label: 'Набір висоти',
                value: '${route.ascentM} м',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.speed_outlined,
                label: 'Темп',
                value: pace,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2E7D32), size: 22),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
