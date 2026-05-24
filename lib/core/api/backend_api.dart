import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Виклик Supabase Edge Functions з єдиним розбором відповіді.
class BackendApi {
  BackendApi({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> invoke(
    String name, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final response = await _client.functions
        .invoke(name, body: body ?? {})
        .timeout(timeout);

    final data = _asMap(response.data);
    if (response.status >= 400 || data?['error'] != null) {
      final code = data?['error']?.toString() ?? 'edge_error';
      final message = data?['message']?.toString() ??
          'Помилка сервера (HTTP ${response.status})';
      throw BackendApiException(code, message);
    }
    return data ?? {};
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
}

class BackendApiException implements Exception {
  final String code;
  final String message;

  BackendApiException(this.code, this.message);

  @override
  String toString() => message;
}
