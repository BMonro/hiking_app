import 'package:latlong2/latlong.dart';

/// Аргументи для відкриття навігації з попередньо заданою лінією маршруту.
class NavigationRouteArgs {
  final List<LatLng> polyline;
  final bool autoStart;
  final String? title;

  const NavigationRouteArgs({
    required this.polyline,
    this.autoStart = false,
    this.title,
  });
}
