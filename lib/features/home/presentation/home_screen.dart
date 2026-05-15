import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ai/presentation/ai_providers.dart';
import '../../ai/presentation/widgets/ai_chat_panel.dart';
import '../../ai/presentation/widgets/recommended_routes_section.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameAsync = ref.watch(homeDisplayNameProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAFAF7),
        title: const Text('Головна'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(personalizedRoutesProvider);
          ref.invalidate(homeDisplayNameProvider);
          ref.invalidate(profileContextProvider);
          await ref.read(personalizedRoutesProvider.future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              nameAsync.when(
                loading: () => Text(
                  'Вітаємо!',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                error: (_, __) => Text(
                  'Вітаємо!',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                data: (name) => Text(
                  'Вітаємо, $name!',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Персональні поради та маршрути для вашого рівня',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              const RecommendedRoutesSection(),
              const SizedBox(height: 24),
              const AiChatPanel(),
              const SizedBox(height: 24),
              _HomeTile(
                icon: Icons.book_outlined,
                title: 'Журнал походів',
                subtitle: 'Нотатки, фото та статистика',
                onTap: () => context.go('/journal'),
              ),
              const SizedBox(height: 12),
              _HomeTile(
                icon: Icons.emoji_events_outlined,
                title: 'Досягнення',
                subtitle: 'Ваші нагороди за активність',
                onTap: () => context.push('/achievements'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF0F0E8),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF2E7D32), size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                  ],
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
