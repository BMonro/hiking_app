import 'package:flutter/material.dart';

/// Значення колонки `routes.route_type` у Supabase.
class RouteModel {
  final String id;
  final String title;
  /// `circular` | `linear` | `radial` | `combined`
  final String routeType;
  final String difficulty;
  final double distanceKm;
  final int ascentM;
  final double durationH;
  final String description;
  final String? coverImageUrl;
  final String authorId;
  final DateTime createdAt;

  const RouteModel({
    required this.id,
    required this.title,
    required this.routeType,
    required this.difficulty,
    required this.distanceKm,
    required this.ascentM,
    required this.durationH,
    required this.description,
    this.coverImageUrl,
    required this.authorId,
    required this.createdAt,
  });

  static const List<String> storedRouteTypeKeys = [
    'circular',
    'linear',
    'radial',
    'combined',
  ];

  /// Нормалізація значення з БД / форми.
  static String normalizeStoredRouteType(dynamic raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    if (s.isEmpty) return 'linear';
    return storedRouteTypeKeys.contains(s) ? s : 'linear';
  }

  static String labelUkForRouteType(String key) {
    return switch (key) {
      'circular' => 'Кільцевий',
      'linear' => 'Лінійний',
      'radial' => 'Радіальний',
      'combined' => 'Комбінований',
      _ => key,
    };
  }

  String get routeTypeLabelUk => labelUkForRouteType(routeType);

  factory RouteModel.fromJson(Map<String, dynamic> json) {
    return RouteModel(
      id: json['id'] as String,
      title: json['title'] as String,
      routeType: normalizeStoredRouteType(json['route_type']),
      difficulty: json['difficulty'] as String? ?? 'easy',
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      ascentM: (json['ascent_m'] as num?)?.toInt() ?? 0,
      durationH: (json['duration_h'] as num?)?.toDouble() ?? 0,
      description: json['description'] as String? ?? '',
      coverImageUrl: json['cover_image_url'] as String?,
      authorId: json['author_id'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String get difficultyLabel {
    switch (difficulty) {
      case 'easy':
        return 'Легкий';
      case 'medium':
        return 'Середній';
      case 'hard':
        return 'Важкий';
      default:
        return difficulty;
    }
  }

  Color get difficultyColor {
    switch (difficulty) {
      case 'easy':
        return const Color(0xFF4CAF50);
      case 'medium':
        return const Color(0xFFFF9800);
      case 'hard':
        return const Color(0xFFF44336);
      default:
        return const Color(0xFF4CAF50);
    }
  }
}
