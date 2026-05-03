import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'routes_provider.dart';
import '../domain/route_model.dart';

class StartRouteScreen extends ConsumerStatefulWidget {
  final String routeId;

  const StartRouteScreen({
    super.key,
    required this.routeId,
  });

  @override
  ConsumerState<StartRouteScreen> createState() => _StartRouteScreenState();
}

class _StartRouteScreenState extends ConsumerState<StartRouteScreen> {
  late MapController _mapController;
  bool _isNavigating = false;
  double _currentDistance = 0;
  double _remainingDistance = 0;
  Duration _elapsedTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routesAsync = ref.watch(routesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Навігація маршрутом'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: routesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Помилка: $e'),
            ],
          ),
        ),
        data: (routes) {
          RouteModel? route;
          try {
            route = routes.firstWhere(
              (r) => r.id == widget.routeId,
            );
          } catch (e) {
            route = null;
          }

          if (route == null) {
            return const Center(child: Text('Маршрут не знайдено'));
          }

          return Stack(
            children: [
              // Map
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: const LatLng(50.4501, 30.5234), // Kyiv
                  initialZoom: 13,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.app',
                  ),
                  // Route polyline layer would be added here
                  // with the actual route coordinates
                ],
              ),

              // Bottom navigation panel
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _NavigationPanel(
                  route: route,
                  isNavigating: _isNavigating,
                  currentDistance: _currentDistance,
                  remainingDistance: _remainingDistance,
                  elapsedTime: _elapsedTime,
                  onStart: () => setState(() => _isNavigating = true),
                  onPause: () => setState(() => _isNavigating = false),
                  onStop: () => context.pop(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NavigationPanel extends StatefulWidget {
  final dynamic route;
  final bool isNavigating;
  final double currentDistance;
  final double remainingDistance;
  final Duration elapsedTime;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onStop;

  const _NavigationPanel({
    required this.route,
    required this.isNavigating,
    required this.currentDistance,
    required this.remainingDistance,
    required this.elapsedTime,
    required this.onStart,
    required this.onPause,
    required this.onStop,
  });

  @override
  State<_NavigationPanel> createState() => _NavigationPanelState();
}

class _NavigationPanelState extends State<_NavigationPanel>
    with TickerProviderStateMixin {
  late AnimationController _expandController;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    if (_isExpanded) {
      _expandController.reverse();
    } else {
      _expandController.forward();
    }
    setState(() => _isExpanded = !_isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final hours = widget.elapsedTime.inHours;
    final minutes = widget.elapsedTime.inMinutes % 60;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with expand button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.route.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.currentDistance.toStringAsFixed(2)} км / ${widget.route.distanceKm} км',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _toggleExpanded,
                  icon: AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: const Icon(Icons.expand_less, size: 28),
                  ),
                ),
              ],
            ),
          ),

          // Expanded content
          SizeTransition(
            sizeFactor: Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(parent: _expandController, curve: Curves.easeOut),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Progress bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Прогрес',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${((widget.currentDistance / widget.route.distanceKm) * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value:
                              widget.currentDistance / widget.route.distanceKm,
                          minHeight: 8,
                          backgroundColor: Colors.grey[300],
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF4CAF50),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Statistics
                  Row(
                    children: [
                      _StatItem(
                        label: 'Час',
                        value: '$hours:${minutes.toString().padLeft(2, '0')}',
                        icon: Icons.schedule,
                      ),
                      const SizedBox(width: 16),
                      _StatItem(
                        label: 'Залишилось',
                        value:
                            '${widget.remainingDistance.toStringAsFixed(1)} км',
                        icon: Icons.straighten,
                      ),
                      const SizedBox(width: 16),
                      _StatItem(
                        label: 'Темп',
                        value:
                            '${(widget.currentDistance / (widget.elapsedTime.inMinutes.toDouble() / 60)).toStringAsFixed(1)} км/год',
                        icon: Icons.speed,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: widget.isNavigating
                              ? widget.onPause
                              : widget.onStart,
                          icon: Icon(
                            widget.isNavigating
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                          label: Text(
                            widget.isNavigating ? 'Пауза' : 'Почати',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onStop,
                          icon: const Icon(Icons.stop),
                          label: const Text('Завершити'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
