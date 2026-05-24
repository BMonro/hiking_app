# РОЗДІЛ 4. РЕАЛІЗАЦІЯ ТА ТЕСТУВАННЯ МОБІЛЬНОЇ СИСТЕМИ ДЛЯ ПЛАНУВАННЯ ГІРСЬКИХ ПОХОДІВ

*Готова версія для вставки в пояснювальну записку. Усі фрагменти коду — з репозиторію `lib/` (стан проєкту Hikora 1.0.0+1).*

---

## 4.1. Реалізація серверної частини

Серверну частину застосунку розгорнуто на хмарній платформі **Supabase** без використання окремого VPS-сервера. База даних **PostgreSQL** містить **15 таблиць** та одне представлення **`profile_stats`** з увімкненим механізмом **Row Level Security** для розмежування доступу між користувачами. Автентифікацію реалізовано через **Supabase Auth** з підтримкою входу через email і пароль та **Google OAuth**. Аватари зберігаються в **Supabase Storage** (bucket `avatars`). Структуру серверної частини наведено на **рис. 4.1** (рекомендовано: діаграма `fig_3_2_component_server` або `fig_3_1_deployment` з `docs/rozdim-3-diagramy.puml`).

**Рис. 4.1.** Структура серверної частини застосунку Hikora

---

### 4.1.1. Реалізація серверної логіки через Edge Functions

Серверну логіку, що потребує захищеного доступу до зовнішніх API або складних операцій з даними, реалізовано через **10 Supabase Edge Functions** на базі **Deno**. Перелік функцій та їх призначення наведено у **табл. 4.1**.

**Таблиця 4.1** — Перелік Edge Functions застосунку Hikora

| Edge Function | Призначення |
|---------------|-------------|
| `ai-chat` | ШІ-консультант на головному екрані (OpenAI API) |
| `recommend-routes` | Персоналізовані рекомендації маршрутів (OpenAI або `rankRoutesByProfile`) |
| `weather` | Прогноз погоди через OpenWeatherMap API |
| `trip-actions` | Групові походи: `create`, `update`, `apply`, `decide`, `cancel`, `close`, `complete`, `leave` |
| `trip-chat` | Список і відправка повідомлень у чаті походу + сповіщення `new_message` |
| `save-route` | Атомарне створення та оновлення маршруту з точками |
| `route-hike` | Маршрутизація по стежках (GraphHopper / OSRM) |
| `geosearch` | Геопошук місць і вершин для редактора маршруту |
| `poi-nearby` | Пошук POI поблизу треку (Overpass API) |
| `prepare-offline-route` | Підготовка полілінії для офлайн-пакета |

Ключі зовнішніх API (`OPENAI_API_KEY`, GraphHopper тощо) зберігаються виключно в **Supabase Secrets** і не повинні потрапляти в клієнтський код. Основний шлях для маршрутизації, геопошуку, POI та погоди — відповідні Edge Functions; **Dio** на клієнті використовується для завантаження **OSM-тайлів** і як **резервний** канал прямих викликів API, якщо Edge Function недоступна. Для production-середовища рекомендується забезпечити постійну доступність функцій `route-hike`, `weather`, `geosearch`.

Єдиний виклик Edge Functions з клієнта інкапсульовано в класі **`BackendApi`**:

**Лістинг 4.1** — Уніфікований виклик Edge Function (`lib/core/api/backend_api.dart`)

```dart
Future<Map<String, dynamic>> invoke(
  String name, {
  Map<String, dynamic>? body,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final response = await _client.functions
      .invoke(name, body: body ?? {})
      .timeout(timeout);

  final data = _asMap(response.data);
  if (response.status >= 400 || data?['error'] != null) {
    final code = data?['error']?.toString() ?? 'edge_error';
    final message = data?['message']?.toString() ??
        'Помилка сервера (HTTP ${response.status})';
    throw BackendApiException(code, message);
  }
  return data ?? {};
}
```

**Лістинг 4.2** — Виклик Edge Function рекомендацій маршрутів (`lib/features/ai/data/ai_service.dart`)

```dart
Future<({List<Map<String, String>> items, String source})>
    fetchRecommendations() async {
  final response = await _invoke(
    'recommend-routes',
    {},
    timeout: _recommendTimeout,
  );

  final data = _asMap(response.data);
  if (response.status >= 400 || data?['error'] != null) {
    throw AiServiceException(
      data?['error']?.toString() ?? 'recommend_failed',
    );
  }

  final source = data?['source']?.toString() ?? 'profile';
  final list = data?['recommendations'];
  if (list is! List) return (items: <Map<String, String>>[], source: source);

  final out = <Map<String, String>>[];
  for (final item in list) {
    if (item is! Map) continue;
    final id = item['route_id']?.toString();
    final reason = item['reason']?.toString();
    if (id != null && id.isNotEmpty && reason != null && reason.isNotEmpty) {
      out.add({'route_id': id, 'reason': reason});
    }
  }
  return (items: out, source: source);
}
```

За відсутності `OPENAI_API_KEY` функція `recommend-routes` повертає `source: profile` і список від резервного алгоритму **`rankRoutesByProfile`**, який виконується **на сервері** (у shared-модулі Edge Function), а не в Dart-клієнті. Ідентифікатор користувача в тілі запиту **не передається** — він береться з JWT у заголовку `Authorization`.

---

### 4.1.2. Реалізація доступу до даних

Обмін даними між клієнтом і сервером відбувається через **Supabase Dart SDK** (PostgREST): репозиторії формують запити `.from('table').select()` / `.eq()` / `.upsert()`, результати перетворюються на Dart-моделі **вручну** в шарі `data` (патерн **Repository**, без ORM). Для складних операцій зі збереження маршруту разом із точками використовується Edge Function **`save-route`**, що виконує операції атомарно на сервері.

**Лістинг 4.3** — Збереження маршруту через Edge Function (`lib/features/routes/data/save_route_api.dart`)

```dart
final data = await _api.invoke(
  'save-route',
  body: {
    'action': 'create',
    'title': title,
    'route_type': routeType,
    'description': description,
    'difficulty': difficulty,
    'is_public': isPublic,
    'points': points,
  },
  timeout: const Duration(seconds: 120),
);
return data['route_id'].toString();
```

Для оновлення списку походів і сповіщень використовується **Supabase Realtime** через WebSocket-підписки (`trips`, `trip_participants`, `notifications`, `messages`). Завантажені офлайн-маршрути дублюються записом у таблиці **`offline_routes`**, а файли пакета зберігаються у файловій системі пристрою через **`path_provider`**.

**Лістинг 4.4** — Запис метаданих офлайн-завантаження в БД (`lib/features/routes/data/routes_repository.dart`)

```dart
await _client.from('offline_routes').upsert({
  'user_id': userId,
  'route_id': routeId,
  'downloaded_at': DateTime.now().toUtc().toIso8601String(),
  'tile_cache_mb': tileCacheMb,
});
```

---

## 4.2. Реалізація клієнтської частини

Клієнтський застосунок реалізовано мовою **Dart** у фреймворку **Flutter SDK 3.0+**. Проєкт організовано за принципом **feature-first**: каталог `lib/features/` містить модулі `auth`, `routes`, `navigation`, `weather`, `trips`, `journal`, `profile`, `ai`, `home`. Кожен модуль поділено на шари **presentation**, **data** та **domain**. Спільна інфраструктура зосереджена в `lib/core/`. Управління станом реалізовано бібліотекою **flutter_riverpod**, навігація — через **go_router**. Структуру клієнтської частини подано на **рис. 4.2** (рекомендовано: `fig_3_2_component_client` з `docs/rozdim-3-diagramy.puml`).

**Рис. 4.2.** Структура клієнтської частини застосунку

---

### 4.2.1. Реалізація навігації та захисту маршрутів

Навігацію між екранами реалізовано через **go_router** із захистом маршрутів на основі стану сесії. Маршрутизатор перевіряє наявність активного JWT-токену та додатково перевіряє заповненість фізичного профілю: якщо користувач увійшов через Google OAuth, але не заповнив профіль (поле `age` відсутнє в таблиці `profiles`), він перенаправляється на `/register?oauth=1`.

**Лістинг 4.5** — Перевірка сесії та заповненості профілю (`lib/core/router/app_router.dart`)

```dart
redirect: (context, state) async {
  try {
    final session = Supabase.instance.client.auth.currentSession;
    final loc = state.matchedLocation;
    final isLoggedIn = session != null;
    final isLoginRoute = loc == '/login';
    final isRegisterRoute = loc == '/register';

    if (!isLoggedIn) {
      if (isLoginRoute || isRegisterRoute) return null;
      return '/login';
    }

    final userId = session.user.id;
    final needsPhysical = await _needsPhysicalProfile(userId);

    if (needsPhysical) {
      if (isRegisterRoute) return null;
      return '/register?oauth=1';
    }

    if (!needsPhysical) {
      if (isRegisterRoute || isLoginRoute) return '/home';
    }

    return null;
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('GoRouter redirect error: $e\n$st');
    }
    return '/login';
  }
},
```

**Лістинг 4.6** — Перевірка заповнення фізичного профілю (`lib/core/router/app_router.dart`)

```dart
Future<bool> _needsPhysicalProfile(String userId) async {
  final profile = await Supabase.instance.client
      .from('profiles')
      .select('age')
      .eq('id', userId)
      .maybeSingle();
  return profile == null || profile['age'] == null;
}
```

**Лістинг 4.7** — Параметр офлайн-only навігації (`lib/core/router/app_router.dart`)

```dart
NavigationScreen(
  routeId: state.pathParameters['routeId']!,
  forceOfflineNavigation:
      state.uri.queryParameters['offline'] == 'true',
),
```

---

### 4.2.2. Реалізація маршрутів, геопошуку та збереження

Каталог публічних маршрутів завантажується через **`RoutesRepository`** з фільтрацією за складністю, типом маршруту (`circular` / `linear` / `radial` / `combined`), тривалістю, набором висоти та пошуком за назвою. Точки маршруту завантажуються **окремим** запитом у методі `getRouteDetail`, а не в `getRoutes`.

**Лістинг 4.8** — Формування запиту до PostgREST з фільтрами (`lib/features/routes/data/routes_repository.dart`)

```dart
Future<List<RouteModel>> getRoutes({
  String? search,
  String? difficulty,
  String? routeType,
  double? durationMax,
  int? ascentMax,
}) async {
  dynamic query = _client.from('routes').select().eq('is_public', true);

  if (search != null && search.isNotEmpty) {
    query = query.ilike('title', '%$search%');
  }
  if (difficulty != null && difficulty != 'all') {
    query = query.eq('difficulty', difficulty);
  }
  if (routeType != null &&
      routeType.isNotEmpty &&
      routeType != 'all') {
    query = query.eq('route_type', routeType);
  }
  if (durationMax != null && durationMax > 0) {
    query = query.lte('duration_h', durationMax);
  }
  if (ascentMax != null && ascentMax > 0) {
    query = query.lte('ascent_m', ascentMax);
  }

  query = query.order('created_at', ascending: false);
  final data = await query;
  return (data as List)
      .map((json) => RouteModel.fromJson(json))
      .toList();
}
```

Геопошук місць та вершин для редактора маршруту виконується через Edge Function **`geosearch`**. Побудова лінії маршруту — через **`route-hike`**; у разі недоступності Edge `RoutingRepository` звертається до API маршрутизації **локально** через Dio.

**Лістинг 4.9** — Маршрутизація через Edge Function `route-hike` (`lib/features/navigation/data/routing_repository.dart`)

```dart
final data = await _api.invoke(
  'route-hike',
  body: {
    'waypoints': waypoints
        .map((p) => {'lat': p.latitude, 'lon': p.longitude})
        .toList(),
  },
  timeout: const Duration(seconds: 90),
);
return _parseEdgePoints(data['points']);
```

Збереження маршруту разом із усіма точками виконується атомарно через Edge Function **`save-route`** (див. лістинг 4.3).

---

### 4.2.3. Реалізація офлайн-карт та навігації

Сервіс **`OfflineMapService`** реалізує метод **`downloadRouteMap`**, який повертає потік прогресу **`OfflineMapDownloadProgress`**. Лінію шляху для офлайн-пакета підготовляє Edge Function **`prepare-offline-route`**.

**Лістинг 4.10** — Підготовка полілінії на сервері (`lib/features/navigation/data/prepare_offline_api.dart`)

```dart
final data = await _api.invoke(
  'prepare-offline-route',
  body: {'route_id': routeId},
  timeout: const Duration(seconds: 120),
);
```

У каталозі `offline_tiles/{routeId}` зберігаються тайли OpenStreetMap (рівні масштабу **11–16**), файл лінії **`route_path.json`**, метадані **`map_meta.json`** та маркер **`.complete`**. Тайли завантажуються через **Dio**.

**Лістинг 4.11** — Завантаження офлайн-пакета (фрагмент `lib/features/navigation/data/offline_map_service.dart`)

```dart
Stream<OfflineMapDownloadProgress> downloadRouteMap(
  RouteDetail detail, {
  required List<LatLng> pathPolyline,
}) async* {
  final routeId = detail.route.id;
  if (pathPolyline.length < 2) {
    throw StateError('Немає лінії маршруту для збереження');
  }

  final points = [...pathPolyline, ...detail.waypoints.map((w) => w.position)];
  final bounds = _boundsForPoints(points);
  final tiles = <({int z, int x, int y})>[];
  for (var z = minZoom; z <= maxZoom; z++) {
    tiles.addAll(_tilesForBounds(bounds, z));
  }

  final dir = await _routeDir(routeId);
  // … завантаження тайлів OSM через Dio (пакетами по 6) …

  await _writePath(
    routeId,
    OfflineRoutePath(
      routeId: routeId,
      title: detail.route.title,
      polyline: pathPolyline,
      waypoints: detail.waypoints,
    ),
  );

  await _writeMeta(routeId, _MapMeta(/* метадані */));
  await marker.writeAsString('1', flush: true); // файл .complete
}
```

**Лістинг 4.12** — Оркестрація завантаження з екрана деталей маршруту (`lib/features/routes/presentation/route_details_screen.dart`)

```dart
final pathPolyline =
    await resolveRoutePathPolyline(widget.detail, routingRepo);

await for (final progress in offlineService.downloadRouteMap(
  widget.detail,
  pathPolyline: pathPolyline,
)) {
  if (!mounted) return;
  setState(() => _progress = progress.fraction);
}

final sizeMb = await offlineService.cacheSizeMb(widget.routeId);
await routesRepo.saveOfflineRoute(widget.routeId, sizeMb);
```

Реалізовано **два режими навігації**:

1. **Класична** (з екрана деталей маршруту) — онлайн: перебудова треку при відхиленні через `route-hike`, шар POI через `poi-nearby`, fallback тайлів на OSM.
2. **Офлайн-only** (вкладка «Офлайн» у «Мої маршрути», параметр `offline=true`) — без мережевих запитів до API маршрутизації та Supabase для маршруту.

На екрані **`NavigationScreen`** відображається поточна позиція GPS з обертанням маркера за курсом, пройдена частина маршруту (сірий) та залишкова (зелений). При відхиленні в онлайн-режимі система показує **SnackBar** та перебудовує трек. Результат роботи навігаційного екрану наведено на **рис. 4.3**.

**Рис. 4.3.** Екран навігації під час активного походу

---

### 4.2.4. Реалізація групових походів

Створення та редагування походу реалізовано через Edge Function **`trip-actions`** (дії `create`, `update`). Заявки та рішення організатора — `apply`, `decide`, `cancel`.

**Лістинг 4.13** — Створення групового походу (`lib/features/trips/data/trips_api.dart`)

```dart
final data = await _invoke({
  'action': 'create',
  'title': title,
  'description': description,
  'meeting_point': meetingPoint,
  'max_members': maxMembers,
  'start_date': startDate,
  'end_date': endDate,
  if (routeId != null) 'route_id': routeId,
});
return (
  tripId: data['trip_id'].toString(),
  tripCode: data['trip_code']?.toString() ?? '',
);
```

Відправка повідомлень у груповому чаті виконується через Edge Function **`trip-chat`**; повідомлення зберігаються в таблиці **`messages`** з доступом лише для учасників зі статусом `approved` через RLS-політики.

**Лістинг 4.14** — Відправка повідомлення в чат (`lib/features/trips/data/trip_chat_api.dart`)

```dart
final data = await _api.invoke(
  'trip-chat',
  body: {
    'action': 'send',
    'trip_id': tripId,
    'content': content,
  },
);
```

Список походів оновлюється через **Supabase Realtime**. Екран групових походів — **`GroupHikesScreen`**, маршрут `/trips`, вкладка «Групи» нижньої панелі.

---

### 4.2.5. Реалізація погоди, журналу та профілю

Модуль погоди: **`WeatherRepository`** викликає Edge Function **`weather`**, яка звертається до OpenWeatherMap на сервері; Dio застосовується як резервний канал.

**Лістинг 4.15** — Запит погоди за координатами (`lib/features/weather/data/weather_repository.dart`)

```dart
final data = await _api.invoke(
  'weather',
  body: {'action': 'both', 'lat': lat, 'lon': lon},
);
```

Доступні екрани `/weather` та погода на маршруті (`/routes/detail/:id/weather`, action `route` на сервері).

Журнал реалізовано через таблиці **`journal_entries`** та **`journal_photos`**; після завершення маршруту система пропонує діалог збереження запису (`navigation_complete_dialog`). Профіль охоплює редагування особистих даних, статистику через представлення **`profile_stats`**, досягнення з автонарахуванням **тригерами в БД** (`achievements_auto_grant.sql`), налаштування та вкладку «Мої маршрути» з офлайн-пакетами.

**Лістинг 4.16** — Вхід через Google OAuth (`lib/features/auth/presentation/login_screen.dart`)

```dart
final launched = await Supabase.instance.client.auth.signInWithOAuth(
  OAuthProvider.google,
  redirectTo: kIsWeb ? null : 'io.supabase.flutter://login-callback/',
);
```

---

## 4.3. Результати реалізації застосунку

У цьому підрозділі наведено результати реалізації застосунку у вигляді демонстрації його роботи. Розглянуто основні сценарії використання: авторизацію, планування маршруту, навігацію, групові походи та ведення журналу. Інструкцію користувача подано у **додатку М**.

### 4.3.1. Демонстрація авторизації та налаштування профілю

Робота із застосунком розпочинається з екрана авторизації (**рис. 4.4**), де користувач вводить email і пароль або входить через Google. Після першої реєстрації через Google маршрутизатор перевіряє заповненість профілю та перенаправляє на екран первинного налаштування, де вказуються вік, рівень фізичної підготовки та медичні обмеження.

**Рис. 4.4.** Екран авторизації застосунку

### 4.3.2. Демонстрація головного екрану та ШІ-рекомендацій

На головному екрані відображається блок персоналізованих рекомендацій маршрутів та вікно ШІ-консультанта (**рис. 4.5**). Рекомендації підбираються через Edge Function `recommend-routes` з урахуванням профілю користувача. За відсутності `OPENAI_API_KEY` джерело рекомендацій — резервний алгоритм ранжування на сервері (`source: profile`).

**Рис. 4.5.** Головний екран з рекомендаціями та ШІ-консультантом

### 4.3.3. Демонстрація роботи з маршрутами

Каталог маршрутів підтримує пошук за назвою та фільтрацію за складністю, типом, тривалістю та набором висоти. При відкритті деталей маршруту відображається інтерактивна карта з треком, перелік ключових точок та кнопки завантаження офлайн-пакета і початку навігації (**рис. 4.6**).

**Рис. 4.6.** Екран деталей маршруту

### 4.3.4. Демонстрація групових походів

Розділ групових походів дозволяє переглядати опубліковані заходи, подавати заявки та спілкуватись у груповому чаті після підтвердження участі (**рис. 4.7**). Організатор переглядає список заявок та ухвалює рішення щодо кожного учасника.

**Рис. 4.7.** Екран групових походів та чату

### 4.3.5. Демонстрація журналу походів

Після завершення навігації застосунок пропонує зберегти запис у журнал зі статистикою, нотатками та фотографіями (**рис. 4.8**). Статистика профілю агрегується через представлення `profile_stats` і відображається у вигляді графіків на екрані профілю.

**Рис. 4.8.** Екран журналу походів

---

## Додатково: відповідність лістингів файлам у репозиторії

| Лістинг | Файл |
|---------|------|
| 4.1 | `lib/core/api/backend_api.dart` |
| 4.2 | `lib/features/ai/data/ai_service.dart` |
| 4.3 | `lib/features/routes/data/save_route_api.dart` |
| 4.4 | `lib/features/routes/data/routes_repository.dart` |
| 4.5–4.7 | `lib/core/router/app_router.dart` |
| 4.8 | `lib/features/routes/data/routes_repository.dart` |
| 4.9 | `lib/features/navigation/data/routing_repository.dart` |
| 4.10 | `lib/features/navigation/data/prepare_offline_api.dart` |
| 4.11 | `lib/features/navigation/data/offline_map_service.dart` |
| 4.12 | `lib/features/routes/presentation/route_details_screen.dart` |
| 4.13–4.14 | `lib/features/trips/data/trips_api.dart`, `trip_chat_api.dart` |
| 4.15 | `lib/features/weather/data/weather_repository.dart` |
| 4.16 | `lib/features/auth/presentation/login_screen.dart` |

*Детальні зауваження та чеклист — у `docs/rozdim-4-vypavlennya-ta-fragmenty-kodu.md`.*
