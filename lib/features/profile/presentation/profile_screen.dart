import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

final profileProvider = FutureProvider((ref) async {
  final userId = Supabase.instance.client.auth.currentUser!.id;
  final data = await Supabase.instance.client
      .from('profiles')
      .select()
      .eq('id', userId)
      .maybeSingle();
  return data;
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Профіль',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            profileAsync.when(
              loading: () => Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    const Center(
                      child: SizedBox(
                        height: 96,
                        width: 96,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFF7BC5A0),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text('?',
                                style: TextStyle(
                                  fontSize: 36,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                )),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Center(
                      child: Text(
                        'Завантаження профілю...',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: const [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0xFFE8F5E9),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(12)),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0xFFE8F5E9),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(12)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              error: (_, __) => const SizedBox(),
              data: (profile) {
                final name = profile?['full_name'] as String?;
                final initials = name != null && name.isNotEmpty
                    ? name.trim().split(' ').map((e) => e[0]).take(2).join()
                    : (user?.email?[0].toUpperCase() ?? '?');
                final fitnessLevel = profile?['fitness_level'] as String?;
                return Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 42,
                            backgroundColor: const Color(0xFF2E7D32),
                            child: Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 30,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name ?? user?.email ?? '',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _getFitnessLabel(fitnessLevel),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8F5E9),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        'Tourist level',
                                        style: TextStyle(
                                          color: Color(0xFF2E7D32),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F8E9),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        fitnessLevel != null
                                            ? fitnessLevel.capitalize()
                                            : 'Невідомо',
                                        style: TextStyle(
                                          color: Colors.green.shade700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => context.go('/edit-profile'),
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Редагувати'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 50,
                            height: 50,
                            child: OutlinedButton(
                              onPressed: () {},
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                side: BorderSide(
                                  color: Colors.green.shade100,
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.share_outlined,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Активність',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[850],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _ActionChip(
                        label: 'План',
                        icon: Icons.map_outlined,
                        color: const Color(0xFF7BC5A0),
                        onTap: () {},
                      ),
                      const SizedBox(width: 10),
                      _ActionChip(
                        label: 'Звіти',
                        icon: Icons.bar_chart_outlined,
                        color: const Color(0xFFFFB347),
                        onTap: () {},
                      ),
                      const SizedBox(width: 10),
                      _ActionChip(
                        label: 'Витрати',
                        icon: Icons.wallet_travel_outlined,
                        color: const Color(0xFF4F83CC),
                        onTap: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Налаштування',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.grey[850],
              ),
            ),
            const SizedBox(height: 12),
            _MenuTile(
              icon: Icons.person_outline,
              iconColor: const Color(0xFF7BC5A0),
              title: 'Мій профіль',
              onTap: () => context.go('/edit-profile'),
            ),
            const SizedBox(height: 10),
            _MenuTile(
              icon: Icons.menu_book_outlined,
              iconColor: const Color(0xFFFFB347),
              title: 'Журнал походів',
              onTap: () => context.go('/journal'),
            ),
            const SizedBox(height: 10),
            _MenuTile(
              icon: Icons.route_outlined,
              iconColor: const Color(0xFF2E7D32),
              title: 'Мої маршрути',
              onTap: () => context.push('/profile/my-routes'),
            ),
            const SizedBox(height: 10),
            _MenuTile(
              icon: Icons.star_outline,
              iconColor: const Color(0xFF4F83CC),
              title: 'Досягнення',
              onTap: () => context.go('/achievements'),
            ),
            const SizedBox(height: 10),
            _MenuTile(
              icon: Icons.settings_outlined,
              iconColor: Colors.grey,
              title: 'Налаштування застосунку',
              onTap: () => context.go('/settings'),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.push('/statistics'),
                icon: const Icon(Icons.bar_chart_rounded, size: 22),
                label: const Text(
                  'Статистика',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF24A175),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (context.mounted) context.go('/login');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade100),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Вийти з акаунту',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getFitnessLabel(String? level) {
    switch (level) {
      case 'beginner':
        return 'Початківець · Карпати';
      case 'intermediate':
        return 'Досвідчений турист · Карпати';
      case 'advanced':
        return 'Експерт · Карпати';
      default:
        return 'Турист · Карпати';
    }
  }

}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        hoverColor: Colors.grey.withOpacity(0.08),
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          hoverColor: color.withOpacity(0.25),
          mouseCursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension _StringCapitalization on String {
  String capitalize() {
    if (isEmpty) return this;
    return substring(0, 1).toUpperCase() + substring(1);
  }
}
