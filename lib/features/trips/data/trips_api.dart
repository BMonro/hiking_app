import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class TripsApi {
  final _client = Supabase.instance.client;

  Future<void> applyToTrip(String tripId) async {
    await _invoke({
      'action': 'apply',
      'trip_id': tripId,
    });
  }

  Future<void> decideParticipant({
    required String tripId,
    required String applicantId,
    required bool approved,
  }) async {
    await _invoke({
      'action': 'decide',
      'trip_id': tripId,
      'applicant_id': applicantId,
      'approved': approved,
    });
  }

  Future<void> cancelTrip(String tripId) async {
    await _invoke({
      'action': 'cancel',
      'trip_id': tripId,
    });
  }

  Future<void> _invoke(Map<String, dynamic> body) async {
    final response = await _client.functions.invoke(
      'trip-actions',
      body: body,
    );

    final data = _asMap(response.data);
    if (response.status >= 400 || data?['error'] != null) {
      throw TripsApiException(_messageFor(data, response.status));
    }
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

  String _messageFor(Map<String, dynamic>? data, int status) {
    final code = data?['error']?.toString();
    return switch (code) {
      'trip_full' => 'Група вже набрана за кількістю місць',
      'trip_not_open' => 'Похід не приймає заявки',
      'already_applied' => 'Заявку вже надіслано',
      'already_member' => 'Ви вже учасник походу',
      'forbidden' => 'Немає прав для цієї дії',
      'organizer_cannot_apply' => 'Організатор не подає заявку на власний похід',
      _ => data?['message']?.toString() ??
          'Помилка операції з походом (HTTP $status)',
    };
  }
}

class TripsApiException implements Exception {
  final String message;
  TripsApiException(this.message);

  @override
  String toString() => message;
}
