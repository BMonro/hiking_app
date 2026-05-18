/// Локально збережена **карта** (тайли OSM) для маршруту — без деталей маршруту.
class OfflineMapPackage {
  final String routeId;
  final String title;
  final DateTime? downloadedAt;
  final int tileCount;

  const OfflineMapPackage({
    required this.routeId,
    required this.title,
    this.downloadedAt,
    this.tileCount = 0,
  });
}
