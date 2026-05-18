import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  List<Map<String, dynamic>> _achievements = [];
  final Set<String> _earned = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAchievements();
  }

  Future<void> _loadAchievements() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;

    final results = await Future.wait([
      client.from('achievements').select(),
      client
          .from('user_achievements')
          .select('achievement_id')
          .eq('user_id', userId),
    ]);

    if (!mounted) return;
    setState(() {
      _achievements = (results[0] as List).cast<Map<String, dynamic>>();
      _earned
        ..clear()
        ..addAll(
          (results[1] as List).map((e) => e['achievement_id'] as String),
        );
      _loading = false;
    });

    // Синхронізація у фоні — не блокує відображення бейджів.
    unawaited(_syncAchievementsInBackground(userId));
  }

  Future<void> _syncAchievementsInBackground(String userId) async {
    try {
      await Supabase.instance.client.rpc('sync_my_achievements');
      if (!mounted) return;
      final userAch = await Supabase.instance.client
          .from('user_achievements')
          .select('achievement_id')
          .eq('user_id', userId);
      if (!mounted) return;
      setState(() {
        _earned
          ..clear()
          ..addAll(
            (userAch as List).map((e) => e['achievement_id'] as String),
          );
      });
    } catch (_) {}
  }

  void _showBadgeDetails({
    required String title,
    required String description,
    required bool earned,
    required IconData icon,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AchievementDetailSheet(
        title: title,
        description: description,
        earned: earned,
        icon: icon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final earnedCount =
        _achievements.where((a) => _earned.contains(a['id'])).length;
    final total = _achievements.length;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAFAF7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/profile');
            }
          },
        ),
        title: const Text(
          'Досягнення',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _achievements.isEmpty
                ? Center(
                    child: Text(
                      'Наразі досягнень немає.',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey[600],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadAchievements,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ваша активність та здобутки',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _ProgressSummary(
                                  earned: earnedCount,
                                  total: total,
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 20,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.72,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final achievement = _achievements[index];
                                final id = achievement['id'] as String;
                                final earned = _earned.contains(id);
                                final title =
                                    achievement['title']?.toString() ?? '';
                                final description =
                                    achievement['description']?.toString() ??
                                        '';
                                final icon = _AchievementIcons.forAchievement(
                                  achievement,
                                );

                                return _AchievementBadge(
                                  title: title,
                                  earned: earned,
                                  icon: icon,
                                  onTap: () => _showBadgeDetails(
                                    title: title,
                                    description: description,
                                    earned: earned,
                                    icon: icon,
                                  ),
                                );
                              },
                              childCount: _achievements.length,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _ProgressSummary extends StatelessWidget {
  final int earned;
  final int total;

  const _ProgressSummary({required this.earned, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? earned / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E8E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Отримано',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '$earned / $total',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2E7D32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFE8ECEA),
              color: const Color(0xFF2E7D32),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementBadge extends StatelessWidget {
  final String title;
  final bool earned;
  final IconData icon;
  final VoidCallback onTap;

  const _AchievementBadge({
    required this.title,
    required this.earned,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BadgeMedallion(earned: earned, icon: icon),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.25,
                fontWeight: earned ? FontWeight.w600 : FontWeight.w500,
                color: earned ? const Color(0xFF1B5E20) : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeMedallion extends StatelessWidget {
  final bool earned;
  final IconData icon;

  const _BadgeMedallion({required this.earned, required this.icon});

  @override
  Widget build(BuildContext context) {
    if (earned) {
      return Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF43A047),
              Color(0xFF2E7D32),
              Color(0xFF1B5E20),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: const Color(0xFFA5D6A7), width: 2.5),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 34),
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFD54F),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 12,
                  color: Color(0xFF5D4037),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFE8EAEC),
        border: Border.all(color: const Color(0xFFD0D5D8), width: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, color: const Color(0xFF9E9E9E), size: 30),
          Positioned(
            right: 8,
            bottom: 8,
            child: Icon(
              Icons.lock_outline,
              size: 16,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementDetailSheet extends StatelessWidget {
  final String title;
  final String description;
  final bool earned;
  final IconData icon;

  const _AchievementDetailSheet({
    required this.title,
    required this.description,
    required this.earned,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BadgeMedallion(earned: earned, icon: icon),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: earned ? const Color(0xFF1B5E20) : Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: earned
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              earned ? 'Отримано' : 'Ще не отримано',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: earned ? const Color(0xFF2E7D32) : Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementIcons {
  static IconData forAchievement(Map<String, dynamic> achievement) {
    final code = achievement['code']?.toString() ?? '';
    final type = achievement['condition_type']?.toString() ?? '';

    return switch (code) {
      'first_hike' => Icons.flag_outlined,
      'hiker_5' => Icons.hiking,
      'hiker_10' => Icons.terrain,
      'hiker_25' => Icons.landscape,
      'km_50' => Icons.directions_walk,
      'km_100' => Icons.straighten,
      'km_500' => Icons.route,
      'ascent_1000' => Icons.trending_up,
      'ascent_5000' => Icons.filter_hdr,
      'route_creator' => Icons.add_location_alt_outlined,
      'route_creator_5' => Icons.map_outlined,
      'reviewer' => Icons.star_outline,
      _ => switch (type) {
          'hikes_count' => Icons.hiking,
          'distance_km' => Icons.straighten,
          'ascent_m' => Icons.trending_up,
          'routes_created' => Icons.map_outlined,
          'rating_given' => Icons.star_outline,
          _ => Icons.emoji_events_outlined,
        },
    };
  }
}
