
class NotificationPreferences {
  const NotificationPreferences({
    this.weatherAlerts = true,
    this.newAchievements = true,
    this.aiRecommendations = false,
    this.tripRequests = true,
    this.tripDecisions = true,
    this.tripChatMessages = true,
  });

  final bool weatherAlerts;
  final bool newAchievements;
  final bool aiRecommendations;
  final bool tripRequests;
  final bool tripDecisions;
  final bool tripChatMessages;

  static const defaults = NotificationPreferences();

  NotificationPreferences copyWith({
    bool? weatherAlerts,
    bool? newAchievements,
    bool? aiRecommendations,
    bool? tripRequests,
    bool? tripDecisions,
    bool? tripChatMessages,
  }) {
    return NotificationPreferences(
      weatherAlerts: weatherAlerts ?? this.weatherAlerts,
      newAchievements: newAchievements ?? this.newAchievements,
      aiRecommendations: aiRecommendations ?? this.aiRecommendations,
      tripRequests: tripRequests ?? this.tripRequests,
      tripDecisions: tripDecisions ?? this.tripDecisions,
      tripChatMessages: tripChatMessages ?? this.tripChatMessages,
    );
  }

  Map<String, dynamic> toJson() => {
        'weatherAlerts': weatherAlerts,
        'newAchievements': newAchievements,
        'aiRecommendations': aiRecommendations,
        'tripRequests': tripRequests,
        'tripDecisions': tripDecisions,
        'tripChatMessages': tripChatMessages,
      };

  factory NotificationPreferences.fromJson(Map<dynamic, dynamic> json) {
    bool b(String key, bool fallback) {
      final v = json[key];
      if (v is bool) return v;
      return fallback;
    }

    return NotificationPreferences(
      weatherAlerts: b('weatherAlerts', true),
      newAchievements: b('newAchievements', true),
      aiRecommendations: b('aiRecommendations', false),
      tripRequests: b('tripRequests', true),
      tripDecisions: b('tripDecisions', true),
      tripChatMessages: b('tripChatMessages', true),
    );
  }

  bool allowsInAppType(String type) {
    switch (type) {
      case 'achievement':
        return newAchievements;
      case 'trip_request':
        return tripRequests;
      case 'trip_approved':
      case 'trip_rejected':
        return tripDecisions;
      case 'new_message':
        return tripChatMessages;
      default:
        return true;
    }
  }
}
