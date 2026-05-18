import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/chat_message.dart';

/// ШІ та рекомендації маршрутів через Supabase Edge Functions.
class AiService {
  AiService();

  final _client = Supabase.instance.client;

  bool? _availableCache;

  /// Скидає кеш після деплою Edge Function або додавання OPENAI_API_KEY.
  void clearAvailabilityCache() => _availableCache = null;

  static const _pingTimeout = Duration(seconds: 5);
  static const _chatTimeout = Duration(seconds: 25);
  static const _recommendTimeout = Duration(seconds: 20);

  Future<bool> isAvailable() async {
    if (_availableCache != null) return _availableCache!;
    try {
      final response = await _client.functions
          .invoke('ai-chat', body: {'ping': true})
          .timeout(_pingTimeout);
      final data = _asMap(response.data);
      _availableCache = response.status == 200 && data?['ok'] == true;
    } on TimeoutException {
      _availableCache = false;
    } on FunctionException {
      _availableCache = false;
    } catch (_) {
      _availableCache = false;
    }
    return _availableCache!;
  }

  Future<String> chat({required List<ChatMessage> history}) async {
    final response = await _invoke(
      'ai-chat',
      {
        'messages': history
            .where((m) => m.role == 'user' || m.role == 'assistant')
            .map((m) => m.toApiPayload())
            .toList(),
      },
      timeout: _chatTimeout,
    );

    final data = _asMap(response.data);
    _throwIfAiError(data, response.status);

    final reply = data?['reply']?.toString().trim();
    if (reply == null || reply.isEmpty) {
      throw AiServiceException('Порожня відповідь від ШІ');
    }
    return reply;
  }

  Future<({List<Map<String, String>> items, String source})>
      fetchRecommendations() async {
    final response = await _invoke(
      'recommend-routes',
      {},
      timeout: _recommendTimeout,
    );

    final data = _asMap(response.data);
    if (response.status >= 400 || data?['error'] != null) {
      throw AiServiceException(
        data?['error']?.toString() ?? 'recommend_failed',
      );
    }

    final source = data?['source']?.toString() ?? 'profile';
    final list = data?['recommendations'];
    if (list is! List) return (items: <Map<String, String>>[], source: source);

    final out = <Map<String, String>>[];
    for (final item in list) {
      if (item is! Map) continue;
      final id = item['route_id']?.toString();
      final reason = item['reason']?.toString();
      if (id != null && id.isNotEmpty && reason != null && reason.isNotEmpty) {
        out.add({'route_id': id, 'reason': reason});
      }
    }
    return (items: out, source: source);
  }

  Future<FunctionResponse> _invoke(
    String name,
    Map<String, dynamic> body, {
    required Duration timeout,
  }) {
    return _client.functions.invoke(name, body: body).timeout(timeout);
  }

  Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  void _throwIfAiError(Map<String, dynamic>? data, int status) {
    if (status == 503 || data?['error'] == 'ai_not_configured') {
      throw AiNotConfiguredException();
    }
    if (data?['error'] != null) {
      throw AiServiceException('Помилка ШІ: ${data!['error']}');
    }
  }
}

class AiNotConfiguredException implements Exception {}

class AiServiceException implements Exception {
  final String message;
  AiServiceException(this.message);

  @override
  String toString() => message;
}
