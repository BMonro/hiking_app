import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PublicProfile {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final int? age;
  final String? fitnessLevel;
  final int experienceCount;
  final String? bio;
  final String? phoneNumber;

  const PublicProfile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.age,
    this.fitnessLevel,
    this.experienceCount = 0,
    this.bio,
    this.phoneNumber,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> json) {
    final name = (json['full_name'] as String?)?.trim();
    final phone = (json['phone_number'] as String?)?.trim();
    return PublicProfile(
      id: json['id']?.toString() ?? '',
      displayName: name != null && name.isNotEmpty ? name : 'Учасник',
      avatarUrl: json['avatar_url'] as String?,
      age: (json['age'] as num?)?.toInt(),
      fitnessLevel: json['fitness_level'] as String?,
      experienceCount: (json['experience_count'] as num?)?.toInt() ?? 0,
      bio: (json['bio'] as String?)?.trim(),
      phoneNumber: phone != null && phone.isNotEmpty ? phone : null,
    );
  }
}

class PublicProfileRepository {
  PublicProfileRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _selectFields =
      'id, full_name, avatar_url, age, fitness_level, experience_count, bio, phone_number';

  Future<PublicProfile?> fetchById(String userId) async {
    if (userId.isEmpty) return null;
    final row = await _client
        .from('profiles_public')
        .select(_selectFields)
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return null;
    return PublicProfile.fromJson(Map<String, dynamic>.from(row));
  }

  Future<Map<String, PublicProfile>> fetchByIds(Iterable<String> userIds) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};
    final rows =
        await _client.from('profiles_public').select(_selectFields).inFilter('id', ids);
    final map = <String, PublicProfile>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final p = PublicProfile.fromJson(row);
      if (p.id.isNotEmpty) map[p.id] = p;
    }
    return map;
  }
}

final publicProfileRepositoryProvider =
    Provider<PublicProfileRepository>((ref) => PublicProfileRepository());
