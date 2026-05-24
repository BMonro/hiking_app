# Навантажувальне тестування Hikora (Apache JMeter)

Перевіряються **Edge Functions** Supabase (серверна логіка), без UI Flutter.

## 0. Швидке відтворення (чеклист)

Усе лежить у `d:\HikingApp\hiking_app\docs\jmeter\`:

| Файл | Навіщо |
|------|--------|
| `hikora_supabase_load.jmx` | План тестів |
| `open_jmeter_gui.ps1` | Запуск GUI |
| `run_jmeter.ps1` | Запуск CLI + HTML-звіт |
| `jmeter.gui.properties` | Без діалогу «file exists» |
| `HIKORA_JMETER_UA.md` | Ця інструкція |

**Кроки:**

1. Встановити **JDK 17+** і **JMeter 5.6+** (§1).
2. PowerShell:
   ```powershell
   cd d:\HikingApp\hiking_app\docs\jmeter
   .\open_jmeter_gui.ps1
   ```
   (якщо JMeter не в `D:\Downloads\...\apache-jmeter-5.6.3`, відредагуйте шлях у `open_jmeter_gui.ps1` або **File → Open** → `hikora_supabase_load.jmx`).
3. **Не зберігайте** старий план з 100/1000 потоків у Setup — **File → Open** знову `hikora_supabase_load.jmx`.
4. Корінь плану → **User Defined Variables**: `TEST_EMAIL`, `TEST_PASSWORD`; опційно `TEST_TRIP_ID`.
5. Перевірити потоки і галочки:
   - **00 Setup** → **1** потік (не 100!), loop **1**
   - **01 Навантаження** → **увімкнено** (галочка), **10** потоків, ramp **10** с, loop **5**
   - Усі samplers під **01** — **увімкнені** (recommend, route-hike, weather, geosearch, poi, REST…, trip-chat)
6. **Aggregate Report** → **Clear** (метла).
7. **Run → Start**.
8. Очікуваний результат: **Auth** = 1 sample, **0%** error; навантаження = **50** samples на sampler (10×5); REST / trip-chat ≈ **0%** error; `poi-nearby` / `recommend-routes` можуть мати помилки (Overpass / AI).

> На скріні з **262 Auth** і **77%** — старі результати або Setup був **100+** потоків. Після кроків 3–7 має бути **1** Auth.

## 1. Встановлення (Windows)

**Варіант A — офіційний архів**

1. Завантажте [Apache JMeter 5.6+](https://jmeter.apache.org/download_jmeter.cgi) (zip).
2. Розпакуйте, наприклад у `C:\Tools\apache-jmeter-5.6.3`.
3. **PATH не обов’язковий.** Запам’ятайте шлях до папки, наприклад:
   `C:\Tools\apache-jmeter-5.6.3\bin\jmeter.bat`

**Запуск без PATH (PowerShell):**

```powershell
# Замініть шлях на те, куди ВИ розпакували архів:
& "C:\Tools\apache-jmeter-5.6.3\bin\jmeter.bat" -t "d:\HikingApp\hiking_app\docs\jmeter\hikora_supabase_load.jmx"
```

**Відкривайте лише один файл:**  
`d:\HikingApp\hiking_app\docs\jmeter\hikora_supabase_load.jmx`  

Не зберігайте копію як `Hikora Supabase Edge Functions.jmx` — JMeter створює дублікат і можна випадково вимкнути весь план.

У меню: **File → Open** → `hikora_supabase_load.jmx`

Після відкриття зліва має з’явитися дерево:
`Hikora Supabase Edge Functions` → `00 Setup - Login JWT` → `01 Навантаження Edge Functions`.

**Варіант B — Chocolatey**

```powershell
choco install jmeter -y
```

Перевірка: `jmeter -v`

> Потрібен **JDK 17+** (`java -version`). JMeter без Java не запуститься.

## 2. Підготовка облікового запису

Потрібен **реальний** користувач застосунку (email + пароль), під яким ви вже входили в Hikora.

У файлі `hikora_supabase_load.jmx` відкрийте **User Defined Variables** і задайте:

| Змінна | Приклад |
|--------|---------|
| `TEST_EMAIL` | `your@email.com` |
| `TEST_PASSWORD` | ваш пароль |
| `TEST_TRIP_ID` | (опційно) UUID походу, де ви організатор або **approved** учасник |

`SUPABASE_HOST` і `ANON_KEY` уже заповнені з проєкту.

## 3. Що вимірює план

Edge Functions у навантаженні (без **ai-chat**):

| Запит | Endpoint |
|-------|----------|
| recommend-routes | `POST /functions/v1/recommend-routes` |
| route-hike | `POST /functions/v1/route-hike` |
| weather | `POST /functions/v1/weather` |
| geosearch | `POST /functions/v1/geosearch` |
| poi-nearby | `POST /functions/v1/poi-nearby` |
| prepare-offline-route | `POST /functions/v1/prepare-offline-route` |
| trip-chat (list) | `POST /functions/v1/trip-chat` |

### Setup (один раз)

| Запит | Endpoint | Призначення |
|-------|----------|-------------|
| Auth | `POST /auth/v1/token` | JWT → `HIKORA_JWT` |
| Route id | `GET /rest/v1/routes?...` | `HIKORA_ROUTE_ID` для офлайн |
| Trip id | `GET /rest/v1/trip_participants?...` | `HIKORA_TRIP_ID` (або `TEST_TRIP_ID`) |

### Маршрути та карта

| Запит | Endpoint |
|-------|----------|
| recommend-routes | `POST /functions/v1/recommend-routes` |
| route-hike | `POST /functions/v1/route-hike` |
| weather | `POST /functions/v1/weather` |
| geosearch | `POST /functions/v1/geosearch` |
| poi-nearby | `POST /functions/v1/poi-nearby` |
| REST routes | `GET /rest/v1/routes?...` |
| prepare-offline-route | `POST /functions/v1/prepare-offline-route` |

### Групові походи

| Запит | Endpoint |
|-------|----------|
| REST trips (open) | Каталог відкритих походів |
| REST trip detail | Картка походу за `HIKORA_TRIP_ID` |
| REST trip participants | Учасники / заявки |
| REST trip messages | Читання чату (PostgreSQL) |
| REST notifications | Сповіщення користувача |
| trip-chat (list) | `POST /functions/v1/trip-chat` |

**Setup «00 Login JWT»** — **1 потік**, **Stop Test on error** (якщо логін не 200 — перевірте email/пароль).  
**Thread Group «01 Навантаження»** — **10** користувачів, розгін **10 с**, **5** циклів (налаштовується в GUI).

## 4. Запуск

### GUI (перший раз — перевірка)

**Рекомендовано** (уникає помилки `Could not delete ... bin`):

```powershell
cd d:\HikingApp\hiking_app\docs\jmeter
.\open_jmeter_gui.ps1
```

Скрипт підхоплює `jmeter.gui.properties` (автоматичний **APPEND** у файл результатів, не в `bin`).

Альтернатива: закрийте JMeter повністю → **File → Open** → `hikora_supabase_load.jmx`.

1. Клікніть корінь **Hikora Supabase Edge Functions** → **User Defined Variables** → `TEST_EMAIL` і `TEST_PASSWORD` (локально; не комітьте пароль у git).
2. **Run → Start** (Ctrl+R). У **Summary Report (Hikora)** файл результатів:  
   `D:/HikingApp/hiking_app/docs/jmeter/results/hikora_gui.jtl` (не папка `bin`).
3. Дивіться **View Results Tree** (коди 200), **Summary Report (Hikora)** / **Aggregate Report (Hikora)**.
4. Якщо з’явилось **«The file already exists»** — **Append** або **Overwrite** (тепер це файл `.jtl`, не `bin`).

Запис у `.jtl` — лише через CLI (§4 CLI) у `docs/jmeter/results/`, не в папку `bin` JMeter.

### CLI (для звіту в дипломі)

```powershell
cd d:\HikingApp\hiking_app\docs\jmeter
jmeter -n -t hikora_supabase_load.jmx -l results\run_01.jtl -e -o results\report_01
```

- `run_01.jtl` — сирі результати.
- `report_01/` — HTML-звіт (відкрийте `index.html`).

Параметри з командного рядка (без зміни JMX):

```powershell
jmeter -n -t hikora_supabase_load.jmx -l results\run.jtl `
  -JTEST_EMAIL=your@email.com -JTEST_PASSWORD=YourPass `
  -e -o results\report
```

## 5. Що писати в пояснювальній (§4.4)

Приклад формулювання:

> Орієнтовне навантажувальне тестування серверних функцій виконано засобом Apache JMeter 5.6: 10 паралельних потоків, 5 ітерацій на потік, Wi‑Fi. Виміряно час відгуку Edge Functions `recommend-routes`, `route-hike`, `weather`. Результати наведено в табл. 4.5 / додатку (скрін Summary Report або HTML-звіт JMeter).

Типові орієнтири (залежать від мережі та OpenAI):

| Операція | Очікуваний порядок |
|----------|-------------------|
| `route-hike` | 1–5 с |
| `weather` | 0.5–2 с |
| `recommend-routes` (AI) | 3–15 с |
| `recommend-routes` (profile) | &lt; 1 с |

## 6. Усунення пробил

| Проблема | Рішення |
|----------|---------|
| 401 майже на всіх Edge | **Auth** = **200**; перезавантажте JMX (токен у `${__property(HIKORA_JWT)}`); **Run Thread Groups consecutively** |
| `__P called with wrong number of parameters` | У Supabase Headers має бути `${__property(HIKORA_JWT)}`, не `${__P(JWT,,)}`. File → Open без збереження старого JMX |
| 401 на Edge | Перевірте email/пароль; JWT прострочився — перезапустіть тест |
| 429 signup/auth | Зачекайте; не запускайте багато потоків на реєстрацію |
| SSL handshake | У JMeter: Options → SSL Manager → не чіпати, якщо стандартний HTTPS |
| `HTTPsampler.Arguments is unset` | Перезавантажте оновлений `hikora_supabase_load.jmx` (прибрано HTTP Request Defaults) |
| `No enabled thread groups found` | Логін у Setup впав → увімкніть **01 Навантаження** (галочка) і виправте email/пароль; див. View Results Tree → Auth |
| Setup «Shutdown» за 1 с | **Auth** не 200: у Body має бути `${TEST_EMAIL}`, не `CHANGE_ME`; перевірте обліковий запис у Hikora |
| `ArrayIndexOutOfBoundsException` при Start | У дереві знята галочка з **Hikora Supabase Edge Functions** (весь план вимкнено) — увімкніть; або File → Open оновлений `hikora_supabase_load.jmx` |
| Warning «file already exists» | **Don't start** → зніміть **Write results to file** у всіх listeners; Filename порожній |
| `Could not delete existing file ... bin` | Запускайте через `.\open_jmeter_gui.ps1` або в **Summary Report** Filename = `D:/HikingApp/.../results/hikora_gui.jtl`, не `...\bin` |
| `recommend-routes` повільний | Нормально при `OPENAI_API_KEY`; для стабільного навантаження тимчасово вимкніть ключ і перевірте `source: profile` |
| `prepare-offline-route` 404 | Немає публічних маршрутів — додайте маршрут у БД або вимкніть sampler |
| `trip-chat` 403 | Немає походу з доступом: створіть похід у застосунку, станьте учасником, або задайте `TEST_TRIP_ID` |
| `REST trip detail` порожньо | Немає `HIKORA_TRIP_ID` — див. Setup або `TEST_TRIP_ID` |
| **Auth** багато помилок (429, 77%+) | У **Setup** має бути **1** потік, не 100/1000; Supabase блокує масовий логін |
| У звіті **тільки Auth** | Логін не 200 → тест зупинився; виправте пароль; **Clear** у Aggregate Report; Setup = **1** потік |

## 7. Файли

- `hikora_supabase_load.jmx` — план тестів
- `open_jmeter_gui.ps1` — GUI без помилки `bin`
- `run_jmeter.ps1` — швидкий запуск CLI
- `results/` — каталог для `.jtl` і HTML (створюється при запуску)
