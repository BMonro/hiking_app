import '../../routes/domain/route_model.dart';

class RouteRecommendation {
  final RouteModel route;
  final String reason;

  const RouteRecommendation({
    required this.route,
    required this.reason,
  });
}
