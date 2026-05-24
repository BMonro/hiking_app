# РОЗДІЛ 4. РЕАЛІЗАЦІЯ ТА ТЕСТУВАННЯ МОБІЛЬНОГО ЗАСТОСУНКУ HIKORA

*Виправлена редакція з урахуванням фактичної реалізації в репозиторії `hiking_app`.*

---

## 4.1. Реалізація (поступово: БД → бекенд → клієнт)

У Word оформити **послідовні підрозділи** (див. `docs/rozdim-4-realizatsiya-ta-testuvannya.md`):

1. **4.1.1** PostgreSQL — 15 таблиць, RLS, seed, Storage policies  
2. **4.1.2** Supabase — Auth, PostgREST, Storage, Realtime (підключення проєкту)  
3. **4.1.3** Edge Functions — 10 функцій BFF  
4. **4.1.4** Контракт API — JWT, Repository, `BackendApi`  
5. **4.2.0** Flutter — `Supabase.initialize`, PKCE, `go_router`  
6. **4.2.1–4.2.5** — модулі UI  

Серверну частину застосунку розгорнуто на хмарній платформі **Supabase** без окремого VPS. База даних **PostgreSQL** містить **15 таблиць** та одне представлення **`profile_stats`** з увімкненим **Row Level Security (RLS)**.

Таблиці: `profiles`, `profile_health_conditions`, `routes`, `route_points`, `route_ratings`, `saved_routes`, `offline_routes`, `trips`, `trip_participants`, `messages`, `journal_entries`, `journal_photos`, `achievements`, `user_achievements`, `notifications`. Облікові записи — у **`auth.users`** (Supabase Auth).

**Автентифікація:** email/пароль, Google OAuth, відновлення пароля. Після OAuth — заповнення фізичного профілю (вік, рівень підготовки).

**Edge Functions (Deno)** — шар BFF: ключі зовнішніх API лише в Supabase Secrets.

| Функція | Призначення |
|---------|-------------|
| `ai-chat` | Діалоговий ШІ-консультант (OpenAI `gpt-4o-mini`) |
| `recommend-routes` | Персоналізовані рекомендації; резерв — `rankRoutesByProfile` |
| `trip-actions` | Заявки на похід: `apply`, `decide`, `cancel` |
| `route-hike` | Пішохідна маршрутизація (GraphHopper/OSRM на сервері) |
| `prepare-offline-route` | Полілінія для офлайн-пакета |
| `save-route` | Збереження маршруту з метриками та точками |
| `weather` | Погода (OpenWeatherMap) |
| `geosearch` | Геопошук (Nominatim/Overpass) |
| `poi-nearby` | POI на карті (Overpass) |
| `trip-chat` | Допоміжні операції групового чату |

**Обмін даними:** Supabase Dart SDK (PostgREST) — репозиторії `.from().select()/.eq()/.upsert()`, мапування в Dart-моделі вручну (**Repository**, без ORM). Зовнішні API з клієнта — переважно через **`BackendApi.invoke()`** → Edge Functions; **Dio** — для тайлів OSM та локальний fallback.

**Realtime:** оновлення списку походів (`tripsRealtimeSyncProvider`). **Storage:** bucket `avatars`. **Офлайн:** метадані в `offline_routes`, файли — `offline_tiles/{routeId}/` на пристрої.

Структуру серверної частини — **рис. 4.1**.

---

## 4.2. Реалізація клієнтської частини

Клієнт: **Dart**, **Flutter SDK 3.0+**, **feature-first** (`lib/features/`): `auth`, `home`, `routes`, `navigation`, `weather`, `group_hikes`, `trips`, `journal`, `profile`, `ai`. Шари: `presentation`, `data`, `domain`. Інфраструктура: `lib/core/` (`app_router`, `MainShell`, `AppTheme`, `BackendApi`).

**Стан:** `flutter_riverpod`. **Навігація:** `go_router` — неавторизований → `/login`; після OAuth без профілю → `/register?oauth=1`.

**Нижня панель:** Головна | Маршрути | Карта | Групи | Профіль.

```dart
redirect: (context, state) async {
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) {
    final loc = state.matchedLocation;
    if (loc == '/login' || loc == '/register') return null;
    return '/login';
  }
  // перевірка age у profiles → /register?oauth=1
  return null;
},
```

**Google OAuth:**

```dart
await Supabase.instance.client.auth.signInWithOAuth(
  OAuthProvider.google,
  redirectTo: kIsWeb ? null : 'io.supabase.flutter://login-callback/',
);
```

Структуру клієнта — **рис. 4.2**.

### 4.2.1. Маршрути та геопошук

`RoutesRepository` — каталог з фільтрами (складність, `route_type`, тривалість, набір висоти, пошук). Точки — у `getRouteDetail`. Збереження — Edge **`save-route`**.

`OsmNominatimService` → **`geosearch`** (fallback — прямий Nominatim/Overpass). Маршрутизація — **`route-hike`** через `RoutingRepository` (fallback — GraphHopper/OSRM з клієнта).

```dart
dynamic query = _client.from('routes').select().eq('is_public', true);
if (search != null && search.isNotEmpty) {
  query = query.ilike('title', '%$search%');
}
// ... difficulty, route_type, duration_h, ascent_m ...
query = query.order('created_at', ascending: false);
```

### 4.2.2. Офлайн-карти та навігація

`OfflineMapService.downloadRouteMap()` — тайли OSM (zoom 11–16) у `offline_tiles/{routeId}/`, `route_path.json`, `map_meta.json`, `.complete`. Лінія — **`prepare-offline-route`** (`PrepareOfflineApi`). Запис у `offline_routes`.

**Два режими:**
1. **Онлайн** — з деталей маршруту: reroute, POI (`poi-nearby`), fallback тайлів.
2. **Офлайн-only** — Профіль → Мої маршрути → Офлайн → `offline=true`.

GPS з обертанням маркера; сірий/зелений трек; відхилення в онлайн — SnackBar + перебудова. **Рис. 4.3.**

### 4.2.3. ШІ

`recommend-routes` → `recommendations` + `source` (`ai` / `profile`). JWT на сервері, `body: {}`. `getRoutesByIds` на клієнті. `ai-chat` на головній. `OPENAI_API_KEY` — лише в Secrets.

### 4.2.4. Групові походи

Форма створення, `trip-actions`, Realtime, чат (`messages`, RLS `approved`). Екран — **`GroupHikesScreen`**, маршрут `/trips`.

### 4.2.5. Погода, журнал, профіль

- **Погода:** `WeatherRepository` → Edge **`weather`**; екрани `/weather`, погода на маршруті.
- **Журнал:** `journal_entries`, `journal_photos`; після походу — діалог завершення.
- **Профіль:** статистика (`profile_stats`), досягнення (тригери БД), налаштування.

---

## 4.3. Результати реалізації

Перевірка на Android. Рис. 4.4–4.8: авторизація, головна з ШІ, каталог, групи, журнал.

---

## 4.4. Тестування (порядок у тексті!)

1. **Функціональне** — 63 випадки, табл. 4.3, скріни в Додатку Л  
2. **Безпека + MobSF** — 37 ST (`run_security_tests_st.py`), MobSF APK, `flutter analyze`, табл. 4.4  
3. **Навантаження** — JMeter `hikora_supabase_load.jmx`, Aggregate Report (рис. 4.7), табл. 4.5  

**Не** ставити JMeter перед функціональним/безпекою.

**Обмеження:** немає UI для `route_ratings` / `saved_routes`; FCM не реалізовано; офлайн лише для завантажених маршрутів.

---

## 4.5. Висновки

Реалізовано підсистеми: auth, маршрути, офлайн-навігація (2 режими), погода, походи, ШІ, журнал, досягнення. Supabase + Edge Functions BFF. Тестування пройдено; протоколи — додаток Л, інструкція — додаток М.
