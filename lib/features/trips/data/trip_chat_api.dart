import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/backend_api.dart';
import 'trip_messages_repository.dart';

/// Чат групового походу через Edge Function `trip-chat`.
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
  }) async {
    try {
      final data = await _api.invoke(
        'trip-chat',
        body: {
          'action': 'send',
          'trip_id': tripId,
          'content': content,
        },
      );
      final msg = data['message'];
      if (msg is Map) {
        return Map<String, dynamic>.from(msg);
      }
      throw StateError('empty_message');
    } on BackendApiException catch (e) {
      if (e.code == 'forbidden') rethrow;
      return _sendDirect(tripId, content);
    } on FunctionException catch (e) {
      final details = _parseDetails(e.details);
      if (details?['error'] == 'forbidden') {
        throw TripChatException('Немає доступу до чату групи');
      }
      return _sendDirect(tripId, content);
    } catch (_) {
      return _sendDirect(tripId, content);
    }
  }

  Future<Map<String, dynamic>> _sendDirect(
    String tripId,
    String content,
  ) async {
    final uid = _client.auth.currentUser!.id;
    final row = await _client
        .from('messages')
        .insert({
          'trip_id': tripId,
          'sender_id': uid,
          'content': content,
        })
        .select('id, trip_id, sender_id, content, sent_at')
        .single();
    return enrichTripMessageRow(Map<String, dynamic>.from(row));
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
