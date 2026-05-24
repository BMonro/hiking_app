# Зміни у розділі 4 (порівняно з rozd4_hikora (1).docx)

## Головні доповнення за кодом Hikora

| Тема | Було в docx | Стало |
|------|-------------|--------|
| Edge Functions | 3 функції (ai-chat, recommend-routes, trip-actions) | **10 функцій** + BFF-шар: route-hike, prepare-offline-route, save-route, weather, geosearch, poi-nearby, trip-chat |
| Зовнішні API | «Dio → GraphHopper/OSRM/OpenWeather» | Переважно **BackendApi → Edge**; Dio — тайли OSM і fallback |
| Модулі клієнта | без group_hikes | **group_hikes** + trips; нижня панель: Головна, Маршрути, **Карта**, Групи, Профіль |
| Офлайн-лінія | лише downloadRouteMap | + **prepare-offline-route** (PrepareOfflineApi) |
| POI на карті | згадано загально | **poi-nearby** (Overpass через Edge) |
| Збереження маршруту | не згадано | **save-route** |
| Погода / журнал | коротко в висновках | **§4.2.5** — weather Edge, journal, profile_stats, achievements |
| getRoutes | `\$search` (помилка) | `%$search%` |
| ШІ | gpt не названо | **gpt-4o-mini**, JWT без user_id у body |

## Що залишено без змін (вже було правильно)

- 15 таблиць + profile_stats  
- Repository без ORM  
- offline_tiles/{routeId}, route_path.json, .complete  
- Два режими навігації, offline=true  
- Google redirect `io.supabase.flutter://login-callback/`  
- 12 тест-кейсів, 3 дефекти, обмеження ratings/saved_routes/FCM  

## Файли

| Файл | Призначення |
|------|-------------|
| `d:\Downloads\rozd4_hikora_vypravleno.docx` | **Готовий Word для здачі** (скопіюйте рисунки 4.1–4.8 зі старого файлу) |
| `docs/rozd4-hikora-vypavlennya.md` | Текстова версія для редагування |
| `docs/rozd4-zmina-do-vypravlennya.md` | Цей перелік змін |

## Що зробити вручну

1. Відкрийте **rozd4_hikora_vypravleno.docx**  
2. Вставте **рисунки 4.1–4.8** та **таблиці 4.1–4.3** з оригінального `rozd4_hikora (1).docx`  
3. Перевірте підписи до рисунків на серверній діаграмі (оновлений список Edge Functions)
