import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profile/data/public_profile_repository.dart';

Future<List<Map<String, dynamic>>> fetchTripMessages(String tripId) async {
  final client = Supabase.instance.client;
  final rows = await client
      .from('messages')
      .select('id, trip_id, sender_id, content, sent_at, reply_to_id')
      .eq('trip_id', tripId)
      .order('sent_at', ascending: true);
  final list = List<Map<String, dynamic>>.from(rows);
  if (list.isEmpty) return list;
  await _attachSenderProfiles(list);
  attachReplyPreviews(list);
  return list;
}

void attachReplyPreviews(List<Map<String, dynamic>> list) {
  final byId = <String, Map<String, dynamic>>{};
  for (final m in list) {
    final id = m['id']?.toString();
    if (id != null && id.isNotEmpty) byId[id] = m;
  }
  for (final m in list) {
    final replyId = m['reply_to_id']?.toString();
    if (replyId == null || replyId.isEmpty) continue;
    final parent = byId[replyId];
    if (parent != null) {
      m['_reply_sender_label'] = parent['_sender_label'] ?? 'Учасник';
      m['_reply_content'] = parent['content']?.toString() ?? '';
    } else {
      m['_reply_sender_label'] = null;
      m['_reply_content'] = null;
    }
  }
}

Future<void> _attachSenderProfiles(List<Map<String, dynamic>> list) async {
  final ids = list.map((m) => m['sender_id']).whereType<String>().toSet();
  if (ids.isEmpty) return;

  final repo = PublicProfileRepository();
  final byId = await repo.fetchByIds(ids);

  for (final m in list) {
    final sid = m['sender_id']?.toString();
    final p = sid != null ? byId[sid] : null;
    m['_sender_label'] = p?.displayName ?? 'Учасник';
    m['_sender_avatar_url'] = p?.avatarUrl;
    m['_sender_age'] = p?.age;
    m['_sender_fitness_level'] = p?.fitnessLevel;
    m['_sender_bio'] = p?.bio;
    m['_sender_experience_count'] = p?.experienceCount;
  }
}

Future<Map<String, dynamic>> enrichTripMessageRow(
  Map<String, dynamic> row,
) async {
  final copy = Map<String, dynamic>.from(row);
  await _attachSenderProfiles([copy]);
  return copy;
}
