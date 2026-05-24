import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../routes/presentation/routes_provider.dart';
import '../data/ai_service.dart';
import '../domain/chat_message.dart';
import '../domain/route_recommendation.dart';

final aiServiceProvider = Provider((ref) => AiService());

final aiConfiguredProvider = FutureProvider<bool>((ref) async {
  return ref.watch(aiServiceProvider).isAvailable();
});

final aiChatSendingProvider = StateProvider<bool>((ref) => false);

final recommendationSourceProvider = StateProvider<String?>((ref) => null);

final personalizedRoutesProvider =
    FutureProvider<List<RouteRecommendation>>((ref) async {
  ref.keepAlive();

  final ai = ref.read(aiServiceProvider);

  try {
    final result = await ai.fetchRecommendations();
    ref.read(recommendationSourceProvider.notifier).state = result.source;

    if (result.items.isEmpty) return [];

    final ids = result.items.map((e) => e['route_id']!).toList();
    final routes = await ref.read(routesRepositoryProvider).getRoutesByIds(ids);
    final reasonById = {
      for (final item in result.items) item['route_id']!: item['reason']!,
    };

    return [
      for (final route in routes)
        if (reasonById.containsKey(route.id))
          RouteRecommendation(
            route: route,
            reason: reasonById[route.id]!,
          ),
    ];
  } catch (_) {
    ref.read(recommendationSourceProvider.notifier).state = null;
    return [];
  }
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
    if (_ref.read(aiChatSendingProvider)) return;

    _ref.read(aiChatSendingProvider.notifier).state = true;

    state = [
      ...state,
      ChatMessage(
        role: 'user',
        content: trimmed,
        sentAt: DateTime.now(),
      ),
    ];

    try {
      final ai = _ref.read(aiServiceProvider);
      ai.clearAvailabilityCache();
      if (!await ai.isAvailable()) {
        throw AiNotConfiguredException();
      }

      final history = state.where((m) => m.role != 'system').toList();
      final reply = await ai.chat(history: history);
      state = [
        ...state,
        ChatMessage(
          role: 'assistant',
          content: reply,
          sentAt: DateTime.now(),
        ),
      ];
    } on AiNotConfiguredException {
      _ref.invalidate(aiConfiguredProvider);
      state = [
        ...state,
        ChatMessage(
          role: 'assistant',
          content:
              'ШІ-чат ще не налаштований на сервері. Додайте OPENAI_API_KEY у Supabase (Edge Functions → Secrets) і перезапустіть застосунок. Рекомендації маршрутів працюють за профілем.',
          sentAt: DateTime.now(),
        ),
      ];
    } on AiServiceException catch (e) {
      state = [
        ...state,
        ChatMessage(
          role: 'assistant',
          content: e.message,
          sentAt: DateTime.now(),
        ),
      ];
    } catch (_) {
      state = [
        ...state,
        ChatMessage(
          role: 'assistant',
          content: 'Не вдалося отримати відповідь. Спробуйте пізніше.',
          sentAt: DateTime.now(),
        ),
      ];
    } finally {
      _ref.read(aiChatSendingProvider.notifier).state = false;
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

final homeDisplayNameProvider = FutureProvider<String>((ref) async {
  ref.keepAlive();
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return 'мандрівнику';

  final row = await Supabase.instance.client
      .from('profiles')
      .select('full_name')
      .eq('id', userId)
      .maybeSingle();

  final name = row?['full_name']?.toString().trim();
  if (name != null && name.isNotEmpty) return name.split(' ').first;

  final email = Supabase.instance.client.auth.currentUser?.email;
  if (email != null && email.contains('@')) {
    return email.split('@').first;
  }
  return 'мандрівнику';
});
