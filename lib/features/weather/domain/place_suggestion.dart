/// Обране місце для прогнозу погоди (координати або лише назва для геокодування).
class PlaceSuggestion {
  final String label;
  final double? lat;
  final double? lon;
  final String? type;

  const PlaceSuggestion({
    required this.label,
    required this.lat,
    required this.lon,
    required this.type,
  });

  bool get hasCoords => lat != null && lon != null;
}
