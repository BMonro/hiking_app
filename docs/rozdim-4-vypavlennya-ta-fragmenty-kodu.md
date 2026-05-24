# Розділ 4 — зауваження та фрагменти коду для вставлення

Документ узгоджує текст розділу 4 диплома з фактичною реалізацією **Hikora** (`lib/`, `supabase/`).  
Усі фрагменти взяті з репозиторію; перед вставкою в Word можна скоротити коментарі.

**Джерела в коді:**

| Фрагмент | Файл |
|----------|------|
| A | `lib/features/routes/data/routes_repository.dart` |
| B | `lib/features/auth/presentation/login_screen.dart` |
| C | `lib/core/router/app_router.dart` |
| D | `lib/features/ai/data/ai_service.dart` + `ai_providers.dart` |
| E | `lib/features/navigation/data/offline_map_service.dart` |
| F | `lib/features/routes/data/routes_repository.dart` (offline_routes) |

---

## 1. Обов’язкові виправлення в тексті

### 1.1. Кількість таблиць

| Було в дипломі | Як правильно |
|----------------|--------------|
| «16 таблиць та одне представлення» | **15 таблиць** та **одне представлення** `profile_stats` |

Таблиці: `profiles`, `profile_health_conditions`, `routes`, `route_points`, `route_ratings`, `saved_routes`, `offline_routes`, `trips`, `trip_participants`, `messages`, `journal_entries`, `journal_photos`, `achievements`, `user_achievements`, `notifications`.

---

### 1.2. Структура підрозділів

| Проблема | Дія |
|----------|-----|
| Перший абзац про сервер без номера | Додати заголовок **«4.1 Реалізація серверної частини»** |
| Згадані **Рис. 4.1, 4.2** без малюнків | Вставити діаграми (deployment + структура клієнта) з `docs/rozdim-3-diagramy.puml` (`fig_3_1_deployment`, `fig_3_2_component_layers`) або намалювати аналоги для розділу 4 |
| Підрозділ 4.3 «Результати реалізації» | Залишити як **демонстрацію UI** (рис. 4.4–4.8); не плутати з тестуванням (4.4) |

---

### 1.3. Невірні фрагменти коду (замінити)

| Місце | Помилка | Заміна |
|-------|---------|--------|
| `getRoutes` | `select('*, route_points(*)')` — **немає** у `getRoutes` | Фрагмент **A** нижче |
| Google OAuth | `io.supabase.hikora://…`, метод `signInWithGoogle()` | Фрагмент **B**; redirect `io.supabase.flutter://login-callback/` |
| ШІ | `getAiRecommendations()`, `body: {user_id}`, `data['routes']` | Фрагменти **C**, **D** |
| Офлайн | `downloadOfflinePackage`, шлях `offline/$routeId` | Фрагмент **E**; метод `downloadRouteMap`, шлях `offline_tiles/$routeId` |

---

### 1.4. Доповнення до тексту (рекомендовано)

1. **Таблиця `offline_routes`** — після завантаження пакета запис у БД (`saveOfflineRoute`) + файли на пристрої (фрагмент **F**).
2. **Зовнішні API** у §4.2.1: крім GraphHopper/OSRM — **Overpass** (POI), **Nominatim** (геопошук), **OpenWeatherMap**.
3. **HTTP-клієнт Dio** — завантаження тайлів OSM і зовнішні запити маршрутизації.
4. **Обмеження** (1 абзац у §4.5): немає UI для `route_ratings` / `saved_routes`; FCM push не реалізовано; повний офлайн лише для завантажених маршрутів; Hive у `pubspec.yaml` не використовується в `lib/`.
5. **Модуль «Групи»** — екран `group_hikes`; заявки/чат — `trips`.
6. **Fallback ШІ** — `rankRoutesByProfile` виконується **на сервері** (Edge Function), не в Dart-клієнті.

---

### 1.5. Таблиці тестування

| ID | Уточнення |
|----|-----------|
| TC-02, TC-04 | Колонку «Результат» краще назвати **«Статус тесту: Пройдено»** (негативний сценарій перевірено, а не «операція успішна») |
| TC-07 | Шлях: **Профіль → Мої маршрути → вкладка «Офлайн»** → навігація з `offline=true` |
| TC-08 | Перебудова маршруту — **лише онлайн-режим** (без `offline=true`) |
| TC-11 | Секрет у Supabase: **`OPENAI_API_KEY`**, не `OPENAI_KEY`; очікування — `source: profile` у відповіді Edge Function |

---

### 1.6. Рисунки 4.4–4.8

- **4.5** — видно блок рекомендацій (навіть при `source: profile`).
- **4.6** — кнопки «Завантажити офлайн» і перехід на навігацію.
- **4.7** — екран **групових походів** (`/groups`), окремо можна чат походу.
- **4.8** — журнал після діалогу завершення походу.

---

## 2. Готові фрагменти коду для вставлення в диплом

### Фрагмент A — отримання відфільтрованого каталогу маршрутів

*Підпис у дипломі:* «Фрагмент коду репозиторію маршрутів — формування запиту до PostgREST з фільтрами»

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

**Примітка для тексту:** точки маршруту (`route_points`) завантажуються окремим запитом у методі `getRouteDetail`, а не в `getRoutes`.

---

### Фрагмент A2 (опційно) — завантаження деталей маршруту з точками

*Якщо потрібно показати роботу з пов’язаними таблицями:*

```dart
final pointsRows = await _client
    .from('route_points')
    .select()
    .eq('route_id', routeId)
    .order('sort_order', ascending: true);
```

---

### Фрагмент B — вхід через Google OAuth

*Підпис:* «Фрагмент екрану авторизації — OAuth через Supabase Auth»

```dart
final launched = await Supabase.instance.client.auth.signInWithOAuth(
  OAuthProvider.google,
  redirectTo: kIsWeb ? null : 'io.supabase.flutter://login-callback/',
);
```

**Примітка:** окремого методу `signInWithGoogle()` у проєкті немає; логіка в `_submitGoogle()` на `LoginScreen`.

---

### Фрагмент C — захист маршрутів (go_router)

*Підпис:* «Фрагмент перевірки сесії та перенаправлення неавторизованого користувача»

```dart
redirect: (context, state) async {
  final session = Supabase.instance.client.auth.currentSession;
  final loc = state.matchedLocation;
  final isLoggedIn = session != null;

  if (!isLoggedIn) {
    if (loc == '/login' || loc == '/register') return null;
    return '/login';
  }
  // … перевірка заповнення фізичного профілю …
  return null;
},
```

---

### Фрагмент C2 — два режими навігації

*Підпис:* «Параметр маршруту для офлайн-only навігації»

```dart
NavigationScreen(
  routeId: state.pathParameters['routeId']!,
  forceOfflineNavigation:
      state.uri.queryParameters['offline'] == 'true',
),
```

**Текст поруч:** класична навігація — з екрана деталей маршруту; офлайн-only — з **Профіль → Мої маршрути → Офлайн**.

---

### Фрагмент D — виклик Edge Function рекомендацій

*Підпис:* «Фрагмент сервісу ШІ — виклик `recommend-routes`»*

```dart
Future<({List<Map<String, String>> items, String source})>
    fetchRecommendations() async {
  final response = await _client.functions.invoke(
    'recommend-routes',
    body: {},
  );
  final data = _asMap(response.data);
  final source = data?['source']?.toString() ?? 'profile';
  final list = data?['recommendations'];
  // … розбір route_id та reason …
  return (items: out, source: source);
}
```

---

### Фрагмент D2 — підвантаження маршрутів на клієнті

*Підпис:* «Провайдер рекомендацій — зв’язок відповіді Edge Function із каталогом»*

```dart
final result = await ai.fetchRecommendations();
final ids = result.items.map((e) => e['route_id']!).toList();
final routes = await ref.read(routesRepositoryProvider).getRoutesByIds(ids);
```

**Примітка:** `user_id` у body **не передається** — ідентифікатор користувача береться з JWT на сервері. При відсутності OpenAI сервер повертає `source: 'profile'` і список від `rankRoutesByProfile`.

---

### Фрагмент E — завантаження офлайн-пакета

*Підпис:* «Фрагмент сервісу офлайн-карт — завантаження тайлів і збереження лінії маршруту»*

```dart
Stream<OfflineMapDownloadProgress> downloadRouteMap(
  RouteDetail detail, {
  required List<LatLng> pathPolyline,
}) async* {
  final routeId = detail.route.id;
  final dir = await _routeDir(routeId); // …/offline_tiles/{routeId}
  // … завантаження тайлів OSM (zoom 11–16) через Dio …
  await _writePath(routeId, OfflineRoutePath(/* polyline, waypoints */));
  await _writeMeta(routeId, _MapMeta(/* метадані */));
  await marker.writeAsString('1', flush: true); // файл .complete
}
```

**Константи сервісу:** `minZoom = 11`, `maxZoom = 16`; шаблон тайлів — `https://tile.openstreetmap.org/{z}/{x}/{y}.png`.

**Файли пакета на пристрої:**

| Файл | Призначення |
|------|-------------|
| `{z}/{x}/{y}.png` | Тайли карти |
| `route_path.json` | Полілінія та waypoints |
| `map_meta.json` | Метадані завантаження |
| `.complete` | Маркер успішного завершення |

---

### Фрагмент F — синхронізація офлайн-маршрутів із БД

*Підпис:* «Фрагмент збереження запису про офлайн-завантаження в таблиці `offline_routes`»*

```dart
await _client.from('offline_routes').upsert({
  'user_id': userId,
  'route_id': routeId,
  'downloaded_at': DateTime.now().toUtc().toIso8601String(),
  'tile_cache_mb': tileCacheMb,
});
```

---

## 3. Готові заміни абзаців (копіювати в Word)

### 3.1. Серверна частина (абзац після опису Edge Functions)

> Обмін даними між клієнтом і сервером відбувається через **Supabase Dart SDK** (PostgREST): репозиторії формують запити `.from('table').select()` / `.eq()` / `.upsert()`, результати перетворюються на Dart-моделі **вручну** в шарі `data` (патерн Repository, без ORM). Для оновлення списку походів і сповіщень використовується **Supabase Realtime** (WebSocket). Завантажені офлайн-маршрути дублюються записом у таблиці `offline_routes`, а файли пакета (тайли, `route_path.json`) зберігаються у файловій системі пристрою через `path_provider`.

### 3.2. ШІ (замість старого абзацу з getAiRecommendations)

> Модуль штучного інтелекту реалізовано через Edge Function **`recommend-routes`**, яка повертає список `recommendations` (ідентифікатор маршруту та текстове обґрунтування) і поле `source` (`ai` або `profile`). Клієнтський `AiService` викликає функцію без передачі `user_id` у тілі запиту — автентифікація виконується за JWT. Далі `personalizedRoutesProvider` завантажує повні картки маршрутів через `getRoutesByIds`. Діалоговий консультант реалізовано функцією **`ai-chat`**. Ключ **OPENAI_API_KEY** зберігається лише в Supabase Secrets.

### 3.3. Офлайн-навігація (замість downloadOfflinePackage)

> Сервіс `OfflineMapService` реалізує метод **`downloadRouteMap`**, який повертає потік прогресу `OfflineMapDownloadProgress`. У каталозі `offline_tiles/{routeId}` зберігаються тайли OpenStreetMap (рівні масштабу 11–16), файл лінії `route_path.json`, метадані `map_meta.json` та маркер `.complete`. Реалізовано два режими: **класична онлайн-навігація** (перебудова треку, POI) та **офлайн-only** (`/navigation?routeId=…&offline=true` з вкладки «Офлайн» у «Мої маршрути»).

### 3.4. Обмеження (додати в §4.5)

> У поточній версії не реалізовано інтерфейс оцінювання маршрутів (`route_ratings`) та збережених маршрутів (`saved_routes`), хоча відповідні таблиці є в БД. Мобільні push-сповіщення (FCM) не використовуються; події походів доставляються через запис у `notifications` та оновлення UI (Realtime, SnackBar).

---

## 4. Оновлена таблиця 4.1 (рекомендовані формулювання)

| ID | Модуль | Тестовий випадок | Статус тесту |
|----|--------|------------------|--------------|
| TC-01 | Auth | Реєстрація з валідним email | Пройдено |
| TC-02 | Auth | Вхід з невірним паролем — відображення помилки | Пройдено |
| TC-03 | Routes | Пошук маршруту за назвою | Пройдено |
| TC-04 | Routes | Створення маршруту без фінішу — блокування валідацією | Пройдено |
| TC-05 | Routes | Створення валідного маршруту | Пройдено |
| TC-06 | Offline | Завантаження офлайн-пакета та запис у `offline_routes` | Пройдено |
| TC-07 | Navigation | Офлайн-навігація без мережі (вкладка «Офлайн») | Пройдено |
| TC-08 | Navigation | Відхилення в онлайн-режимі — SnackBar і reroute | Пройдено |
| TC-09 | Trips | Подача заявки на похід | Пройдено |
| TC-10 | Trips | Схвалення заявки організатором | Пройдено |
| TC-11 | AI | Рекомендації без OPENAI_API_KEY (`source: profile`) | Пройдено |
| TC-12 | Journal | Збереження запису після походу | Пройдено |

---

## 5. Діаграми для Рис. 4.1 та 4.2

| Рисунок | Рекомендація |
|---------|----------------|
| **4.1** Серверна частина | PlantUML: `fig_3_2_component_server` (компоненти Supabase) або `fig_3_1_deployment` (розгортання) |
| **4.2** Клієнтська частина | PlantUML: `fig_3_2_component_client` (модулі та репозиторії) або `fig_3_2_component_layers` (шари) |

Підписи змінити з «3.x» на «4.1», «4.2».

---

## 6. Чеклист перед здачею розділу 4

- [ ] Замінено всі 4 невірні фрагменти коду (getRoutes, OAuth, ШІ, офлайн)
- [ ] Виправлено «16 таблиць» → «15 таблиць + 1 представлення»
- [ ] Додано заголовок **4.1** для серверної частини
- [ ] Вставлено **Рис. 4.1** та **Рис. 4.2**
- [ ] Уточнено шлях офлайн-навігації та два режими
- [ ] Згадано `offline_routes` і Dio
- [ ] У таблиці тестів — «Пройдено» для негативних сценаріїв
- [ ] У висновках зазначено обмеження (ratings, FCM)
- [ ] Додаток Л — протоколи; Додаток М — інструкція користувача

---

*Файл створено для узгодження розділу 4 диплома з кодовою базою Hikora.*
