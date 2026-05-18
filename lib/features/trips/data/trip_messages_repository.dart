import 'package:supabase_flutter/supabase_flutter.dart';

/// Завантажує повідомлення чату походу з іменами відправників.
Future<List<Map<String, dynamic>>> fetchTripMessages(String tripId) async {
  final client = Supabase.instance.client;
  final rows = await client
      .from('messages')
      .select('id, trip_id, sender_id, content, sent_at')
      .eq('trip_id', tripId)
      .order('sent_at', ascending: true);
  final list = List<Map<String, dynamic>>.from(rows);
  if (list.isEmpty) return list;
  await _attachSenderLabels(list);
  return list;
}

Future<void> _attachSenderLabels(List<Map<String, dynamic>> list) async {
  final ids = list.map((m) => m['sender_id']).whereType<String>().toSet().toList();
  if (ids.isEmpty) return;
  final profiles = await Supabase.instance.client
      .from('profiles')
      .select('id, full_name')
      .inFilter('id', ids);
  final nameById = <String, String>{};
  for (final p in List<Map<String, dynamic>>.from(profiles)) {
    final id = p['id']?.toString();
    if (id != null) {
      nameById[id] = (p['full_name'] as String?)?.trim().isNotEmpty == true
          ? p['full_name'] as String
          : 'Користувач';
    }
  }
  for (final m in list) {
    final sid = m['sender_id']?.toString();
    m['_sender_label'] = nameById[sid] ?? 'Учасник';
  }
}

Future<Map<String, dynamic>> enrichTripMessageRow(
  Map<String, dynamic> row,
) async {
  final copy = Map<String, dynamic>.from(row);
  await _attachSenderLabels([copy]);
  return copy;
}
