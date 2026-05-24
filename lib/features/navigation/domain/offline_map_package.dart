/// Локально збережений офлайн-пакет: тайли карти + лінія шляху.
class OfflineMapPackage {
  final String routeId;
  final String title;
  final DateTime? downloadedAt;
  final int tileCount;
  final int pathPointCount;

  const OfflineMapPackage({
    required this.routeId,
    required this.title,
    this.downloadedAt,
    this.tileCount = 0,
    this.pathPointCount = 0,
  });
}
