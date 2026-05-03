import 'package:flutter/material.dart';

/// Точка інтересу з OpenStreetMap (Overpass).
enum MapPoiKind {
  peak,
  water,
  shelter,
  hut,
  viewpoint,
  picnicSite,
  campSite,
  attraction,
  historic,
  information,
  other,
}

class MapPoi {
  final double lat;
  final double lon;
  final String? name;
  final MapPoiKind kind;
  /// Висота над рівнем моря (м), з тега `ele` у OSM, якщо є.
  final int? elevationM;

  const MapPoi({
    required this.lat,
    required this.lon,
    required this.kind,
    this.name,
    this.elevationM,
  });

  /// Парсить тег `ele` (метри), напр. "1234" або "1234 m".
  static int? elevationMFromTags(Map<String, String> tags) {
    final raw = tags['ele']?.trim();
    if (raw == null || raw.isEmpty) return null;
    final first = raw.split(RegExp(r'\s+')).first;
    return int.tryParse(first);
  }

  static MapPoiKind kindFromTags(Map<String, String> tags) {
    if (tags['natural'] == 'peak') return MapPoiKind.peak;

    final natural = tags['natural'] ?? '';
    if (natural == 'spring' || natural == 'hot_spring') {
      return MapPoiKind.water;
    }

    final amenity = tags['amenity'] ?? '';
    if (amenity == 'drinking_water' || amenity == 'fountain') {
      return MapPoiKind.water;
    }
    if (amenity == 'shelter') return MapPoiKind.shelter;

    final manMade = tags['man_made'] ?? '';
    if (manMade == 'water_well') return MapPoiKind.water;

    final tourism = tags['tourism'] ?? '';
    if (tourism == 'picnic_site') return MapPoiKind.picnicSite;
    if (tourism == 'camp_site' || tourism == 'caravan_site') {
      return MapPoiKind.campSite;
    }
    if (tourism == 'alpine_hut' || tourism == 'wilderness_hut') {
      return MapPoiKind.hut;
    }
    if (tourism == 'viewpoint') return MapPoiKind.viewpoint;
    if (tourism == 'attraction' ||
        tourism == 'museum' ||
        tourism == 'gallery' ||
        tourism == 'artwork' ||
        tourism == 'zoo' ||
        tourism == 'theme_park') {
      return MapPoiKind.attraction;
    }
    if (tourism == 'information') return MapPoiKind.information;

    final historic = tags['historic'] ?? '';
    if (historic.isNotEmpty &&
        historic != 'yes' &&
        _historicKinds.contains(historic)) {
      return MapPoiKind.historic;
    }

    return MapPoiKind.other;
  }

  /// Типи `historic=*`, які показуємо як туристичні пам’ятки.
  static const Set<String> _historicKinds = {
    'castle',
    'ruins',
    'archaeological_site',
    'monument',
    'memorial',
    'wayside_shrine',
    'battlefield',
    'fort',
    'city_gate',
    'manor',
  };

  static IconData iconFor(MapPoiKind k) {
    return switch (k) {
      MapPoiKind.peak => Icons.terrain,
      MapPoiKind.water => Icons.water_drop_outlined,
      MapPoiKind.shelter => Icons.night_shelter_outlined,
      MapPoiKind.hut => Icons.cabin_outlined,
      MapPoiKind.viewpoint => Icons.photo_camera_outlined,
      MapPoiKind.picnicSite => Icons.park_outlined,
      MapPoiKind.campSite => Icons.festival_outlined,
      MapPoiKind.attraction => Icons.star_outline,
      MapPoiKind.historic => Icons.account_balance_outlined,
      MapPoiKind.information => Icons.info_outline,
      MapPoiKind.other => Icons.place_outlined,
    };
  }

  static Color colorFor(MapPoiKind k) {
    return switch (k) {
      MapPoiKind.peak => const Color(0xFF5D4037),
      MapPoiKind.water => const Color(0xFF0277BD),
      MapPoiKind.shelter => const Color(0xFF1565C0),
      MapPoiKind.hut => const Color(0xFF6A1B9A),
      MapPoiKind.viewpoint => const Color(0xFFE65100),
      MapPoiKind.picnicSite => const Color(0xFF558B2F),
      MapPoiKind.campSite => const Color(0xFFBF360C),
      MapPoiKind.attraction => const Color(0xFFC62828),
      MapPoiKind.historic => const Color(0xFF6D4C41),
      MapPoiKind.information => const Color(0xFF00897B),
      MapPoiKind.other => const Color(0xFF455A64),
    };
  }

  static String labelUk(MapPoiKind k) {
    return switch (k) {
      MapPoiKind.peak => 'Вершина',
      MapPoiKind.water => 'Вода / джерело',
      MapPoiKind.shelter => 'Притулок',
      MapPoiKind.hut => 'Хатина / притулок',
      MapPoiKind.viewpoint => 'Оглядовий майданчик',
      MapPoiKind.picnicSite => 'Зона пікніка',
      MapPoiKind.campSite => 'Кемпінг',
      MapPoiKind.attraction => 'Туристична атракція',
      MapPoiKind.historic => 'Пам’ятка',
      MapPoiKind.information => 'Інформація',
      MapPoiKind.other => 'Точка інтересу',
    };
  }
}
