import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/route_detail.dart';
import '../domain/route_model.dart';

class RoutesRepository {
  final _client = Supabase.instance.client;

  Future<List<RouteModel>> getRoutes({
    String? search,
    String? difficulty,
    String? routeType,
    double? durationMax,
    int? ascentMax,
  }) async {
    // Усі фільтри мають йти до `.order()` — інакше Postgrest повертає
    // PostgrestTransformBuilder без методів `.ilike()` / `.eq()` тощо.
    dynamic query = _client.from('routes').select().eq('is_public', true);

    if (search != null && search.isNotEmpty) {
      query = query.ilike('title', '%$search%');
    }

    if (difficulty != null && difficulty != 'all') {
      query = query.eq('difficulty', difficulty);
    }

    if (routeType != null &&
        routeType.isNotEmpty &&
        routeType != 'all') {
      query = query.eq('route_type', routeType);
    }

    if (durationMax != null && durationMax > 0) {
      query = query.lte('duration_h', durationMax);
    }

    if (ascentMax != null && ascentMax > 0) {
      query = query.lte('ascent_m', ascentMax);
    }

    query = query.order('created_at', ascending: false);

    final data = await query;
    final routes =
        (data as List).map((json) => RouteModel.fromJson(json)).toList();

    return routes;
  }

  Future<RouteDetail?> getRouteDetail(String routeId) async {
    final row = await _client
        .from('routes')
        .select()
        .eq('id', routeId)
        .maybeSingle();

    if (row == null) return null;

    final route = RouteModel.fromJson(Map<String, dynamic>.from(row));

    final pointsRows = await _client
        .from('route_points')
        .select()
        .eq('route_id', routeId)
        .order('sort_order', ascending: true);

    final waypoints = <RouteWaypoint>[];
    for (final p in (pointsRows as List)) {
      final m = Map<String, dynamic>.from(p as Map);
      final lat = (m['latitude'] as num?)?.toDouble();
      final lon = (m['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      waypoints.add(
        RouteWaypoint(
          name: m['name']?.toString(),
          position: LatLng(lat, lon),
          pointType: m['point_type']?.toString() ?? 'start',
          sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
          altitudeM: (m['altitude_m'] as num?)?.toInt(),
        ),
      );
    }

    final geo = row['geojson'];
    final polyline = parseRoutePolylineFromGeoJson(geo);

    return RouteDetail(
      route: route,
      waypoints: waypoints,
      polyline: polyline,
    );
  }

  Future<void> addRoute(Map<String, dynamic> data) async {
    await _client.from('routes').insert(data);
  }

  Future<String> addRouteReturningId(Map<String, dynamic> data) async {
    final inserted =
        await _client.from('routes').insert(data).select('id').single();
    return inserted['id'].toString();
  }

  Future<void> replaceRoutePoints(
    String routeId,
    List<Map<String, dynamic>> points,
  ) async {
    await _client.from('route_points').delete().eq('route_id', routeId);
    if (points.isEmpty) return;
    await _client.from('route_points').insert(points);
  }

  Future<void> updateRoute(String routeId, Map<String, dynamic> data) async {
    await _client.from('routes').update(data).eq('id', routeId);
  }

  Future<void> deleteRoute(String routeId) async {
    await _client.from('routes').delete().eq('id', routeId);
  }
}
