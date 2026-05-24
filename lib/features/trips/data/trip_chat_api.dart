import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/backend_api.dart';
import '../../profile/data/public_profile_repository.dart';
import 'trip_messages_repository.dart';

class TripChatApi {
  TripChatApi({BackendApi? api, SupabaseClient? client})
      : _api = api ?? BackendApi(),
        _client = client ?? Supabase.instance.client;

  final BackendApi _api;
  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> listMessages(String tripId) async {
    try {
      final data = await _api.invoke(
        'trip-chat',
        body: {'action': 'list', 'trip_id': tripId},
        timeout: const Duration(seconds: 30),
      );
      final raw = data['messages'];
      if (raw is! List) return [];
      return raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return fetchTripMessages(tripId);
    }
  }

  Future<Map<String, dynamic>> sendMessage({
    required String tripId,
    required String content,
    String? replyToId,
  }) async {
    try {
      final data = await _api.invoke(
        'trip-chat',
        body: {
          'action': 'send',
          'trip_id': tripId,
          'content': content,
          if (replyToId != null && replyToId.isNotEmpty)
            'reply_to_id': replyToId,
        },
      );
      final msg = data['message'];
      if (msg is Map) {
        return Map<String, dynamic>.from(msg);
      }
      throw StateError('empty_message');
    } on BackendApiException catch (e) {
      if (e.code == 'forbidden') rethrow;
      return _sendDirect(tripId, content, replyToId: replyToId);
    } on FunctionException catch (e) {
      final details = _parseDetails(e.details);
      if (details?['error'] == 'forbidden') {
        throw TripChatException('Немає доступу до чату групи');
      }
      return _sendDirect(tripId, content, replyToId: replyToId);
    } catch (_) {
      return _sendDirect(tripId, content, replyToId: replyToId);
    }
  }

  Future<Map<String, dynamic>> _sendDirect(
    String tripId,
    String content, {
    String? replyToId,
  }) async {
    final uid = _client.auth.currentUser!.id;
    final insert = <String, dynamic>{
      'trip_id': tripId,
      'sender_id': uid,
      'content': content,
    };
    if (replyToId != null && replyToId.isNotEmpty) {
      insert['reply_to_id'] = replyToId;
    }
    final row = await _client
        .from('messages')
        .insert(insert)
        .select('id, trip_id, sender_id, content, sent_at, reply_to_id')
        .single();
    final enriched = await enrichTripMessageRow(Map<String, dynamic>.from(row));

    if (replyToId != null && replyToId.isNotEmpty) {
      final parent = await _client
          .from('messages')
          .select('id, content, sender_id')
          .eq('id', replyToId)
          .eq('trip_id', tripId)
          .maybeSingle();
      if (parent != null) {
        final withParent = [Map<String, dynamic>.from(parent), enriched];
        await _attachSenderProfilesForReply(withParent);
        enriched['_reply_sender_label'] =
            withParent.first['_sender_label'] ?? 'Учасник';
        enriched['_reply_content'] = parent['content']?.toString() ?? '';
      }
    }
    return enriched;
  }

  Future<void> _attachSenderProfilesForReply(
    List<Map<String, dynamic>> list,
  ) async {
    final ids = list.map((m) => m['sender_id']).whereType<String>().toSet();
    if (ids.isEmpty) return;
    final repo = PublicProfileRepository();
    final byId = await repo.fetchByIds(ids);
    for (final m in list) {
      final sid = m['sender_id']?.toString();
      final p = sid != null ? byId[sid] : null;
      m['_sender_label'] = p?.displayName ?? 'Учасник';
    }
  }

  Map<String, dynamic>? _parseDetails(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return null;
  }
}

class TripChatException implements Exception {
  final String message;
  TripChatException(this.message);

  @override
  String toString() => message;
}
