import 'package:dio/dio.dart';

class ElevationLookupService {
  ElevationLookupService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<int?> fetchElevationM(double lat, double lon) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://api.open-meteo.com/v1/elevation',
        queryParameters: {
          'latitude': lat.toStringAsFixed(5),
          'longitude': lon.toStringAsFixed(5),
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      final list = response.data?['elevation'];
      if (list is List && list.isNotEmpty) {
        final v = list.first;
        if (v is num) return v.round();
      }
    } catch (_) {}
    return null;
  }
}
