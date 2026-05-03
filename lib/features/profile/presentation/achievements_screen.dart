import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  List<Map<String, dynamic>> _achievements = [];
  List<String> _earned = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAchievements();
  }

  Future<void> _loadAchievements() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final all = await Supabase.instance.client.from('achievements').select();
    final userAch = await Supabase.instance.client
        .from('user_achievements')
        .select('achievement_id')
        .eq('user_id', userId);

    setState(() {
      _achievements = (all as List).cast<Map<String, dynamic>>();
      _earned =
          (userAch as List).map((e) => e['achievement_id'] as String).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Досягнення'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ваша активність та здобутки',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
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
                        : ListView.separated(
                            itemCount: _achievements.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final achievement = _achievements[index];
                              final isEarned =
                                  _earned.contains(achievement['id']);
                              return _AchievementCard(
                                title: achievement['title'] ?? '',
                                description: achievement['description'] ?? '',
                                earned: isEarned,
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final String title;
  final String description;
  final bool earned;

  const _AchievementCard({
    required this.title,
    required this.description,
    required this.earned,
  });

  @override
  Widget build(BuildContext context) {
    final color = earned ? const Color(0xFF2E7D32) : Colors.grey[500];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: earned ? const Color(0xFFE8F5E9) : Colors.grey[100],
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: earned ? const Color(0xFFB8E6C3) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor:
                earned ? const Color(0xFF2E7D32) : Colors.grey[350],
            child: Text(
              earned ? '🏅' : '🔒',
              style: const TextStyle(fontSize: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
