import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profile/presentation/profile_screen.dart';
import '../../routes/presentation/routes_provider.dart';
import '../data/ai_service.dart';
import '../data/profile_context_builder.dart';
import '../data/route_recommendation_engine.dart';
import '../domain/chat_message.dart';
import '../domain/route_recommendation.dart';

final aiServiceProvider = Provider((ref) => AiService());

final profileContextProvider = FutureProvider<String>((ref) async {
  return ProfileContextBuilder().build();
});

final personalizedRoutesProvider =
    FutureProvider<List<RouteRecommendation>>((ref) async {
  final repo = ref.read(routesRepositoryProvider);
  final routes = await repo.getRoutes();
  if (routes.isEmpty) return [];

  final profile = await ref.watch(profileProvider.future);
  final ai = ref.read(aiServiceProvider);
  final engine = RouteRecommendationEngine();

  if (!ai.isConfigured) {
    final candidates = engine.rank(profile: profile, routes: routes);
    return candidates
        .map((c) => RouteRecommendation(route: c.route, reason: c.reason))
        .toList();
  }

  try {
    final context = await ref.read(profileContextProvider.future);
    final catalog = routes
        .take(40)
        .map(
          (r) => {
            'id': r.id,
            'title': r.title,
            'difficulty': r.difficulty,
            'distance_km': r.distanceKm,
            'duration_h': r.durationH,
            'ascent_m': r.ascentM,
            'route_type': r.routeType,
            'description': r.description.length > 120
                ? '${r.description.substring(0, 120)}…'
                : r.description,
          },
        )
        .toList();

    final system = '''
Ти експерт з пішохідного туризму в Україні. Обери до 5 маршрутів з каталогу для користувача.
Враховуй рівень підготовки, досвід, бажану складність, тривалість і обмеження здоровʼя.
Не рекомендуй маршрути, що явно перевищують можливості.
Відповідай ТІЛЬКИ JSON українською:
{"recommendations":[{"route_id":"uuid","reason":"коротке пояснення до 120 символів"}]}
''';

    final user = '''
Профіль користувача:
$context

Каталог маршрутів (JSON):
${jsonEncode(catalog)}
''';

    final raw = await ai.completeJson(systemPrompt: system, userPrompt: user);
    final parsed = AiService.parseRecommendationsJson(raw);
    final byId = {for (final r in routes) r.id: r};
    final result = <RouteRecommendation>[];
    for (final item in parsed) {
      final route = byId[item['route_id']];
      if (route == null) continue;
      result.add(
        RouteRecommendation(
          route: route,
          reason: item['reason']!,
        ),
      );
      if (result.length >= 5) break;
    }
    if (result.isNotEmpty) return result;
  } catch (_) {}

  final candidates = engine.rank(profile: profile, routes: routes);
  return candidates
      .map((c) => RouteRecommendation(route: c.route, reason: c.reason))
      .toList();
});

class AiChatNotifier extends StateNotifier<List<ChatMessage>> {
  AiChatNotifier(this._ref) : super(const []);

  final Ref _ref;

  static const _welcome =
      'Привіт! Я ваш порадник з походів. Запитайте про спорядження, підготовку, безпеку на стежці чи вибір маршруту — врахую ваш профіль.';

  void ensureWelcome() {
    if (state.isNotEmpty) return;
    state = [
      ChatMessage(
        role: 'assistant',
        content: _welcome,
        sentAt: DateTime.now(),
      ),
    ];
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final userMsg = ChatMessage(
      role: 'user',
      content: trimmed,
      sentAt: DateTime.now(),
    );
    state = [...state, userMsg];

    try {
      final ai = _ref.read(aiServiceProvider);
      if (!ai.isConfigured) {
        throw AiNotConfiguredException();
      }

      final context = await _ref.read(profileContextProvider.future);
      final system = '''
Ти дружній україномовний порадник з пішохідного туризму в застосунку HikingApp.
Давай практичні, безпечні поради щодо спорядження, підготовки, харчування, погоди, темпу на стежці.
Враховуй профіль користувача нижче. Не вигадуй конкретних GPS-координат.
Якщо питання про медицину — рекомендуй звернутися до лікаря.
Відповідай стисло (до 6 речень), структуровано за потреби.

Профіль:
$context
''';

      final history = state.where((m) => m.role != 'system').toList();
      final reply = await ai.chat(history: history, systemPrompt: system);
      state = [
        ...state,
        ChatMessage(
          role: 'assistant',
          content: reply,
          sentAt: DateTime.now(),
        ),
      ];
    } on AiNotConfiguredException {
      state = [
        ...state,
        ChatMessage(
          role: 'assistant',
          content:
              'ШІ-порадник ще не налаштований. Додайте API-ключ у lib/core/config/ai_config.dart (див. ai_config.example.dart). '
              'Тим часом перегляньте рекомендовані маршрути нижче — вони підібрані за вашим профілем.',
          sentAt: DateTime.now(),
        ),
      ];
    } catch (_) {
      state = [
        ...state,
        ChatMessage(
          role: 'assistant',
          content:
              'Не вдалося отримати відповідь. Перевірте інтернет і ключ API. Спробуйте ще раз.',
          sentAt: DateTime.now(),
        ),
      ];
    }
  }

  void clear() {
    state = [];
    ensureWelcome();
  }
}

final aiChatProvider =
    StateNotifierProvider<AiChatNotifier, List<ChatMessage>>((ref) {
  final notifier = AiChatNotifier(ref);
  notifier.ensureWelcome();
  return notifier;
});

final aiConfiguredProvider = Provider<bool>((ref) {
  return ref.watch(aiServiceProvider).isConfigured;
});

/// Імʼя для привітання на головній.
final homeDisplayNameProvider = FutureProvider<String>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  final name = profile?['full_name']?.toString().trim();
  if (name != null && name.isNotEmpty) return name.split(' ').first;
  final email = Supabase.instance.client.auth.currentUser?.email;
  if (email != null && email.contains('@')) {
    return email.split('@').first;
  }
  return 'мандрівнику';
});
