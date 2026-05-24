
enum MapTileStyle {

  standard,

  terrain,
}

extension MapTileStyleConfig on MapTileStyle {
  String get urlTemplate => switch (this) {
        MapTileStyle.standard =>
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        MapTileStyle.terrain =>
          'https://tile.opentopomap.org/{z}/{x}/{y}.png',
      };

  double? get maxZoom => switch (this) {
        MapTileStyle.standard => null,
        MapTileStyle.terrain => 17,
      };

  MapTileStyle get toggled => switch (this) {
        MapTileStyle.standard => MapTileStyle.terrain,
        MapTileStyle.terrain => MapTileStyle.standard,
      };

  String get toggleTooltip => switch (this) {
        MapTileStyle.standard => 'Увімкнути рельєфну карту',
        MapTileStyle.terrain => 'Звичайна карта',
      };
}

const String openTopoMapAttribution = 'OpenTopoMap (CC-BY-SA)';
