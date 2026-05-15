import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/config/ai_config.dart';
import '../domain/chat_message.dart';

class AiService {
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  bool get isConfigured => AiConfig.isConfigured;

  Future<String> chat({
    required List<ChatMessage> history,
    required String systemPrompt,
  }) async {
    if (!isConfigured) {
      throw AiNotConfiguredException();
    }

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      ...history.map((m) => m.toApiPayload()),
    ];

    return _complete(messages);
  }

  Future<String> completeJson({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    if (!isConfigured) {
      throw AiNotConfiguredException();
    }

    return _complete([
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ], jsonMode: true);
  }

  Future<String> _complete(
    List<Map<String, String>> messages, {
    bool jsonMode = false,
  }) async {
    final body = <String, dynamic>{
      'model': AiConfig.model,
      'messages': messages,
      'temperature': 0.6,
    };
    if (jsonMode) {
      body['response_format'] = {'type': 'json_object'};
    }

    final response = await _dio.post<Map<String, dynamic>>(
      '${AiConfig.baseUrl}/chat/completions',
      data: body,
      options: Options(
        headers: {'Authorization': 'Bearer ${AiConfig.apiKey.trim()}'},
      ),
    );

    final choices = response.data?['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw AiServiceException('Порожня відповідь від ШІ');
    }
    final content =
        (choices.first as Map)['message']?['content']?.toString().trim();
    if (content == null || content.isEmpty) {
      throw AiServiceException('Порожня відповідь від ШІ');
    }
    return content;
  }

  /// Парсить JSON з рекомендаціями: `{ "recommendations": [ { "route_id", "reason" } ] }`.
  static List<Map<String, String>> parseRecommendationsJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return [];
      final list = decoded['recommendations'];
      if (list is! List) return [];
      final out = <Map<String, String>>[];
      for (final item in list) {
        if (item is! Map) continue;
        final id = item['route_id']?.toString();
        final reason = item['reason']?.toString();
        if (id != null && id.isNotEmpty && reason != null && reason.isNotEmpty) {
          out.add({'route_id': id, 'reason': reason});
        }
      }
      return out;
    } catch (_) {
      return [];
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
