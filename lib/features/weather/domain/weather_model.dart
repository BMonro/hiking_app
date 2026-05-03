class WeatherModel {
  final String cityName;
  final double temperature;
  final double feelsLike;
  final String description;
  final String icon;
  final int humidity;
  final double windSpeed;
  final int? pressure;
  final int? visibilityMeters;
  final double lat;
  final double lon;

  const WeatherModel({
    required this.cityName,
    required this.temperature,
    required this.feelsLike,
    required this.description,
    required this.icon,
    required this.humidity,
    required this.windSpeed,
    required this.pressure,
    required this.visibilityMeters,
    required this.lat,
    required this.lon,
  });

  factory WeatherModel.fromJson(Map<String, dynamic> json) {
    return WeatherModel(
      cityName: json['name'] as String? ?? '',
      temperature: (json['main']['temp'] as num).toDouble(),
      feelsLike: (json['main']['feels_like'] as num).toDouble(),
      description: (json['weather'][0]['description'] as String),
      icon: json['weather'][0]['icon'] as String,
      humidity: json['main']['humidity'] as int,
      windSpeed: (json['wind']['speed'] as num).toDouble(),
      pressure: (json['main']['pressure'] as num?)?.toInt(),
      visibilityMeters: (json['visibility'] as num?)?.toInt(),
      lat: (json['coord']['lat'] as num).toDouble(),
      lon: (json['coord']['lon'] as num).toDouble(),
    );
  }

  String get temperatureStr => '${temperature.round()}°C';
  String get feelsLikeStr => '${feelsLike.round()}°C';
  String get iconUrl => 'https://openweathermap.org/img/wn/$icon@2x.png';
}

class WeatherForecastDay {
  final DateTime date;
  final double tempDay;
  final double tempNight;
  final String icon;

  const WeatherForecastDay({
    required this.date,
    required this.tempDay,
    required this.tempNight,
    required this.icon,
  });

  String get dayTempStr => '${tempDay.round()}°';
  String get nightTempStr => '${tempNight.round()}°';
  String get iconUrl => 'https://openweathermap.org/img/wn/$icon@2x.png';
}
