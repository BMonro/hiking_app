import 'package:supabase_flutter/supabase_flutter.dart';

/// Збирає текстовий контекст профілю для ШІ-запитів.
class ProfileContextBuilder {
  final _client = Supabase.instance.client;

  Future<String> build() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 'Користувач не авторизований.';

    final profile = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    final conditions = await _client
        .from('profile_health_conditions')
        .select('condition')
        .eq('user_id', userId);

    final stats = await _client
        .from('profile_stats')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    final fitnessLabels = {
      'beginner': 'початківець',
      'intermediate': 'середній',
      'advanced': 'досвідчений',
    };
    final difficultyLabels = {
      'easy': 'легкий',
      'medium': 'середній',
      'hard': 'важкий',
    };

    final name = profile?['full_name']?.toString().trim();
    final age = profile?['age'];
    final fitness = profile?['fitness_level']?.toString() ?? 'beginner';
    final experience = profile?['experience_count'] ?? 0;
    final prefDiff = profile?['preferred_difficulty']?.toString();
    final prefDuration = profile?['preferred_duration_h'];
    final bio = profile?['bio']?.toString().trim();

    final conditionList = List<Map<String, dynamic>>.from(conditions)
        .map((e) => e['condition']?.toString())
        .whereType<String>()
        .where((c) => c.isNotEmpty)
        .toList();

    final totalHikes = stats?['total_hikes'] ?? 0;
    final totalKm = stats?['total_distance_km'] ?? 0;
    final totalAscent = stats?['total_ascent_m'] ?? 0;

    final buffer = StringBuffer();
    if (name != null && name.isNotEmpty) {
      buffer.writeln('Імʼя: $name');
    }
    if (age != null) buffer.writeln('Вік: $age');
    buffer.writeln(
      'Рівень підготовки: ${fitnessLabels[fitness] ?? fitness}',
    );
    buffer.writeln('Завершених походів (журнал): $experience');
    if (prefDiff != null) {
      buffer.writeln(
        'Бажана складність маршрутів: ${difficultyLabels[prefDiff] ?? prefDiff}',
      );
    }
    if (prefDuration != null) {
      buffer.writeln('Бажана тривалість: $prefDuration год');
    }
    if (conditionList.isNotEmpty) {
      buffer.writeln('Обмеження здоровʼя: ${conditionList.join(', ')}');
    }
    if (bio != null && bio.isNotEmpty) {
      buffer.writeln('Про себе: $bio');
    }
    buffer.writeln(
      'Статистика: $totalHikes походів, $totalKm км, $totalAscent м набору висоти.',
    );

    return buffer.toString().trim();
  }
}
