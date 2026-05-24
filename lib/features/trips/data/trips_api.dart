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

  Future<({String tripId, String tripCode})> createTrip({
    required String title,
    required String description,
    required String meetingPoint,
    required int maxMembers,
    required String startDate,
    required String endDate,
    String? routeId,
  }) async {
    try {
      final data = await _invoke({
        'action': 'create',
        'title': title,
        'description': description,
        'meeting_point': meetingPoint,
        'max_members': maxMembers,
        'start_date': startDate,
        'end_date': endDate,
        if (routeId != null) 'route_id': routeId,
      });
      return (
        tripId: data['trip_id'].toString(),
        tripCode: data['trip_code']?.toString() ?? '',
      );
    } on TripsApiException catch (e) {
      if (_shouldFallbackToDirectDb(e.code)) {
        return _createTripDirect(
          title: title,
          description: description,
          meetingPoint: meetingPoint,
          maxMembers: maxMembers,
          startDate: startDate,
          endDate: endDate,
          routeId: routeId,
        );
      }
      rethrow;
    }
  }

  Future<void> updateTrip({
    required String tripId,
    required String title,
    required String description,
    required String meetingPoint,
    required int maxMembers,
    required String startDate,
    required String endDate,
    String? routeId,
  }) async {
    try {
      await _invoke({
        'action': 'update',
        'trip_id': tripId,
        'title': title,
        'description': description,
        'meeting_point': meetingPoint,
        'max_members': maxMembers,
        'start_date': startDate,
        'end_date': endDate,
        if (routeId != null) 'route_id': routeId,
      });
    } on TripsApiException catch (e) {
      if (_shouldFallbackToDirectDb(e.code)) {
        await _updateTripDirect(
          tripId: tripId,
          title: title,
          description: description,
          meetingPoint: meetingPoint,
          maxMembers: maxMembers,
          startDate: startDate,
          endDate: endDate,
          routeId: routeId,
        );
        return;
      }
      rethrow;
    }
  }

  bool _shouldFallbackToDirectDb(String code) =>
      code == 'action_and_trip_id_required' ||
      code == 'unknown_action' ||
      code == 'action_required';

  Future<({String tripId, String tripCode})> _createTripDirect({
    required String title,
    required String description,
    required String meetingPoint,
    required int maxMembers,
    required String startDate,
    required String endDate,
    String? routeId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw TripsApiException('unauthorized', 'Потрібна авторизація');
    }

    final code =
        'TRIP-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final row = await _client
        .from('trips')
        .insert({
          'title': title,
          'description': description,
          'meeting_point': meetingPoint,
          'max_members': maxMembers,
          'start_date': startDate,
          'end_date': endDate,
          'route_id': routeId,
          'organizer_id': userId,
          'status': 'open',
          'trip_code': code,
        })
        .select('id, trip_code')
        .single();

    return (
      tripId: row['id'].toString(),
      tripCode: row['trip_code']?.toString() ?? code,
    );
  }

  Future<void> _updateTripDirect({
    required String tripId,
    required String title,
    required String description,
    required String meetingPoint,
    required int maxMembers,
    required String startDate,
    required String endDate,
    String? routeId,
  }) async {
    await _client.from('trips').update({
      'title': title,
      'description': description,
      'meeting_point': meetingPoint,
      'max_members': maxMembers,
      'start_date': startDate,
      'end_date': endDate,
      'route_id': routeId,
    }).eq('id', tripId);
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke(
        'trip-actions',
        body: body,
      );

      final data = _asMap(response.data);
      if (response.status >= 400 || data?['error'] != null) {
        final code = data?['error']?.toString() ?? 'edge_error';
        throw TripsApiException(code, _messageFor(data, response.status));
      }
      return data ?? {};
    } on FunctionException catch (e) {
      final data = _asMap(e.details);
      final code = data?['error']?.toString() ?? 'edge_error';
      throw TripsApiException(code, _messageFor(data, e.status));
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
    final code = data?['error']?.toString() ?? '';
    return switch (code) {
      'trip_full' => 'Група вже набрана за кількістю місць',
      'trip_not_open' => 'Похід не приймає заявки',
      'already_applied' => 'Заявку вже надіслано',
      'already_member' => 'Ви вже учасник походу',
      'forbidden' => 'Немає прав для цієї дії',
      'organizer_cannot_apply' => 'Організатор не подає заявку на власний похід',
      'invalid_dates' => 'Некоректні дати походу',
      'title_required' => 'Введіть назву походу',
      'trip_not_editable' => 'Похід більше не редагується',
      'action_and_trip_id_required' =>
        'Оновіть Edge Function trip-actions на сервері (див. DEPLOY_EDGE_FUNCTIONS_UA.txt)',
      _ => data?['message']?.toString() ??
          'Помилка операції з походом (HTTP $status)',
    };
  }
}

class TripsApiException implements Exception {
  final String code;
  final String message;

  TripsApiException(this.code, this.message);

  @override
  String toString() => message;
}
