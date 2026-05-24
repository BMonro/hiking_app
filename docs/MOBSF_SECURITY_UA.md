# Безпека зберігання даних і SAST (MobSF) — Hikora

Для пояснювальної заповнюють рядки методики на кшталт:

| Тип | Інструмент | Що перевіряє |
|-----|------------|--------------|
| **Data Storage Security Testing** | MobSF + ручні перевірки | Локальні файли, Hive, кеш, чи не лежать секрети в APK |
| **SAST** | MobSF (APK) + `flutter analyze` | Статичний аналіз коду / зібраного застосунку |

**Складність:** середня (**3/5**). Перший раз: ~2–4 год (Docker, збірка APK, розбір звіту). Повторно: ~30–60 хв.

Серверні ST-01…ST-31 і Storage API — окремо: `docs/run_security_tests_st.py` (додаток N).

---

## 1. Що саме перевіряємо в Hikora

### На пристрої (MobSF → Data Storage)

- Чи немає **service role / OpenAI (`sk-`)** у APK (дублює ST-29).
- Де зберігаються дані: **Hive** (налаштування сповіщень), **кеш офлайн-карт** (`offline_map_service`), сесія **Supabase** (зазвичай у захищеному сховищі ОС).
- Чи увімкнено **backup** Android, чи є **world-readable** файли, слабкі налаштування `network_security_config`.
- **ANON_KEY** у `lib/core/config/supabase_config.dart` — у MobSF часто **HIGH**; у дипломі: *публічний ключ, захист даних — RLS на сервері* (як у Supabase).

### На сервері (скрипт, не MobSF)

```powershell
py -3 docs/run_security_tests_st.py --edge-only   # ST-29, ST-Storage-1
# з двома акаунтами — повний прогін, включно ST-Storage-2
```

| ID | Перевірка |
|----|-----------|
| ST-Storage-1 | Upload у Storage **без** JWT — має бути відмова |
| ST-Storage-2 | Upload у `avatars/{чужий_uid}-avatar.jpg` під сесією A — RLS має блокувати |

---

## 2. Підготовка (один раз)

### 2.1. Docker Desktop (Windows)

1. [Docker Desktop](https://www.docker.com/products/docker-desktop/) — увімкнено WSL2.
2. Перевірка: `docker --version`

### 2.2. Збірка release APK

```powershell
cd d:\HikingApp\hiking_app
flutter build apk --release
```

APK зазвичай тут:

`build\app\outputs\flutter-apk\app-release.apk`

> Для MobSF без попередження «debug certificate» один раз створіть release keystore:
> `cd android` → `.\create_release_keystore.ps1` → `flutter build apk --release`.
> Без `key.properties` збірка release лишається на debug-ключі (лише для локальної розробки).

### 2.3. Dart SAST (додатково, 5 хв)

```powershell
cd d:\HikingApp\hiking_app
flutter analyze
```

У звіт: «локальний статичний аналіз Dart без критичних попереджень безпеки» (або перелік виправлених info/warning).

---

## 3. Запуск MobSF

```powershell
docker pull opensecurity/mobile-security-framework-mobsf:latest
docker run -it --rm -p 8000:8000 opensecurity/mobile-security-framework-mobsf:latest
```

Браузер: **http://127.0.0.1:8000**

1. **Upload** → вибрати `app-release.apk`.
2. Дочекатися сканування (5–15 хв).
3. Відкрити розділи:
   - **Static Analysis** → **Code Analysis** (SAST)
   - **Static Analysis** → **Manifest Analysis**
   - **Static Analysis** → **NIAP / Storage** або **File Analysis** (Data Storage)
   - **PDF Report** — зберегти для додатку.

---

## 4. Що вставити в пояснювальну (скріни)

| № | Скрін з MobSF | Підпис |
|---|----------------|--------|
| 1 | Dashboard після скану (Score / Critical / High) | Загальна оцінка APK |
| 2 | **Secrets / Hardcoded credentials** | Перевірка витоку ключів (пояснити ANON_KEY) |
| 3 | **SQLite / Hive / Shared User Data** | Локальне зберігання |
| 4 | **Network Security** | HTTPS, cleartext |
| 5 | **Permissions** | Камера, геолокація, інтернет |
| 6 | Вивід `flutter analyze` (термінал) | SAST вихідного коду Dart |
| 7 | Вивід `run_security_tests_st.py` ST-Storage-1/2 | Серверне Storage + RLS |

---

## 5. Як інтерпретувати типові знахідки Hikora

| Знахідка MobSF | Рівень | Що писати в дипломі |
|----------------|--------|---------------------|
| Hardcoded API key (Supabase anon) | High | Допустимо для клієнта; доступ до даних обмежено **RLS** і **JWT** |
| App backup allowed | Medium | **Виправлено:** `android:allowBackup="false"`, `fullBackupContent="false"` |
| Cleartext / weak network | Medium | **Виправлено:** `usesCleartextTraffic="false"` + `network_security_config.xml` |
| Background location | Medium | **Виправлено:** прибрано `ACCESS_BACKGROUND_LOCATION` (навігація — лише на передньому плані) |
| Debug certificate | High | **Виправлення:** `android/create_release_keystore.ps1` + `key.properties` (див. §2.2) |
| minSdk &lt; 29 | Medium | **Виправлено:** `minSdk = 29` (лише Android 10+) |
| ProfileInstallReceiver | Medium | **Виправлено:** `tools:node="remove"` у маніфесті |
| Ensure permissions required | Info | Див. **§5.1** — кожен дозвіл прив’язаний до функції |
| External Storage / temp files (CODE) | Medium | **False positive частково:** код плагінів (`image_picker`); дані додатку — у **private** `getApplicationDocumentsDirectory` |
| App logs information (CODE) | Info | **§5.2** — логи Flutter/geolocator; власний код без секретів у release |
| Clipboard (CODE) | Info | **§5.2** — лише TextField; без `Clipboard` у `lib/` |
| Clear text disabled (NETWORK) | Secure | Підтверджено налаштуваннями маніфесту |
| No trackers (TRACKERS) | Secure | Без рекламних SDK |
| Hive / SQLite файли | Info | Локальні налаштування; без паролів у відкритому вигляді |
| Insecure WebView / HTTP | High (якщо є) | У Hikora має бути лише HTTPS до Supabase |
| Certificate pinning відсутній | Low | Опційне посилення; для курсової/диплома — «рекомендація» |

**Висновок для розділу:** критичних витоків **service key** у клієнті не виявлено (ST-29 + MobSF); серверне Storage захищено політиками; локальне зберігання — переважно Hive/офлайн-кеш без облікових даних у plaintext.

### 5.1. Обґрунтування дозволів (MobSF: «Ensure permissions are required»)

MobSF показує це для **кожного** dangerous permission — це не означає «зайвий дозвіл», а нагадування перевірити необхідність. У Hikora **усі** оголошені дозволи використовуються:

| Дозвіл | Навіщо | Де в коді |
|--------|--------|-----------|
| `ACCESS_FINE_LOCATION` | GPS на маршруті | `lib/features/navigation/presentation/navigation_screen.dart` — `Geolocator.getPositionStream` |
| `ACCESS_COARSE_LOCATION` | Пара до fine на Android 10–11 | той самий модуль geolocator |
| `CAMERA` | Фото аватара з камери | `lib/features/profile/presentation/edit_profile_screen.dart` — `ImageSource.camera` |
| `READ_MEDIA_IMAGES` | Галерея (Android 13+) | журнал, реєстрація, профіль — `ImageSource.gallery` |
| `READ_EXTERNAL_STORAGE` | Галерея (Android 10–12), `maxSdkVersion="32"` | ті самі екрани |
| `INTERNET` | Supabase, Edge Functions, OSM, GraphHopper | увесь застосунок |

**Не оголошуємо:** `WRITE_EXTERNAL_STORAGE`, `ACCESS_BACKGROUND_LOCATION`, `RECORD_AUDIO` — не потрібні.

**Знахідки CODE (External Storage / temp file):** MobSF аналізує **декомпільовані** бібліотеки Flutter/`image_picker` (копія вибраного фото у cache). Власні файли офлайн-карт і Hive — у **закритій** директорії застосунку (`offline_map_service.dart`), не в shared external storage.

### 5.2. Логування та буфер обміну (MobSF CODE)

#### «The App logs information» (десятки файлів `A/a.java`, `FlutterJNI.java`, `GeolocatorLocationService.java`…)

| Що бачить MobSF | Реальність у Hikora |
|----------------|---------------------|
| Сотні `Log.d` / `Log.i` у декомпільованому APK | Це **Flutter engine**, **AndroidX**, **geolocator**, не вихідний код `lib/` |
| `com/baseflow/geolocator/GeolocatorLocationService.java` | Служба GPS плагіна; у release не логує паролі користувача |
| `io/flutter/embedding/engine/FlutterJNI.java` | Внутрішні логи рушія Flutter |

**У власному коді (Dart):** жодного `print()` без обмеження; `debugPrint` лише під `kDebugMode`:

- `lib/main.dart` — помилки Supabase / необроблені винятки (тільки debug-збірка)
- `lib/core/router/app_router.dart` — помилки redirect (тільки debug-збірка)

У **release** ці гілки **виключаються компілятором** (`kDebugMode == false`). Паролі, JWT і anon key у логи **не виводяться**.

**Що зроблено в проєкті:**

- `lib/core/logging/app_log.dart` — логи **тільки** в debug.
- Release: **R8** + `proguard-rules.pro` (`-assumenosideeffects` для `android.util.Log`) — **менше** рядків у MobSF після перескану.
- Паролі: `enableInteractiveSelection: false` у полях з `obscureText` (логін, реєстрація, зміна пароля).

**Для диплома:** частина попереджень лишиться (логи Flutter engine); ризик витоку секретів через логи/clipboard у власному коді — **низький**.

#### «This App copies data to clipboard» (`io/flutter/plugin/editing/d.java`, `D0/e.java`)

| Джерело | Пояснення |
|---------|-----------|
| `io/flutter/plugin/editing/` | Стандартний **TextField** / клавіатура: користувач копіює текст у полях (email, назва походу тощо) |
| У `lib/` | **Немає** `Clipboard.setData` — застосунок **сам** не копіює паролі чи токени в буфер |

**Що зроблено:** для паролів вимкнено копіювання/виділення тексту (`enableInteractiveSelection: false`).

**Для диплома:** MobSF все одно бачить API clipboard у `flutter/plugin/editing` (звичайні TextField); пароль у буфер **програмно** не копіюється.

#### Позитивні знахідки (залишити в звіті)

| Знахідка | Значення |
|----------|----------|
| **Base config … disallow clear text** | Підтверджує `network_security_config` + HTTPS |
| **No privacy trackers** | Немає рекламних/трекінгових SDK |

---

## 6. Готовий фрагмент тексту (§4.x)

> **Перевірка безпечності зберігання даних** виконана інструментом **MobSF** (Mobile Security Framework) для зібраного Android APK (`app-release.apk`) та доповнена серверними тестами **ST-Storage-1/2** (політики Supabase Storage). Перевірялось: відсутність секретних ключів AI у клієнті, характер локальних сховищ (Hive, файли офлайн-карт), налаштування мережі (HTTPS), права доступу застосунку.
>
> **SAST** реалізовано як статичний аналіз **MobSF** (декомпіляція та правила OWASP MASVS для APK) і **`flutter analyze`** для вихідного коду Dart. У APK виявлено наявність публічного **anon key** Supabase; це відповідає архітектурі BFF/клієнт–сервер, оскільки авторизація операцій з даними користувача виконується через **JWT** і **Row Level Security**. Завантаження файлів у bucket `avatars` без токена або в каталог іншого користувача заблоковано (ST-Storage-1/2).
>
> За результатами MobSF критичних вразливостей, що дозволяють обійти серверну авторизацію без компрометації облікового запису, не виявлено. У маніфесті: мінімальна платформа Android 10 (API 29), вимкнено backup і cleartext, дозволи відповідають функціям (навігація, фото профілю/журналу). Release APK підписується власним keystore (не debug). Опційно — certificate pinning.

---

## 7. Чеклист «зроблено»

- [ ] `flutter build apk --release`
- [ ] MobSF: upload + PDF-звіт
- [ ] 3–5 скрінів у додаток
- [ ] `flutter analyze` — зберегти вивід
- [ ] `py -3 docs/run_security_tests_st.py` — ST-Storage (з 2 акаунтами для ST-Storage-2)
- [ ] Таблиця в додатку N (ST-29, ST-Storage-1, ST-Storage-2) + посилання на MobSF

---

## 8. Усунення проблем

| Проблема | Рішення |
|----------|---------|
| Docker не стартує | WSL2, перезапуск Docker Desktop |
| Немає APK | `flutter build apk --release`, шлях вище |
| MobSF дуже довго | Нормально для Flutter APK; не закривайте контейнер |
| Занадто багато High | Фільтруйте: Secrets, Storage, Network; ігноруйте false positive для anon key з поясненням |
| ST-Storage 429 | Зачекайте; задайте `HIKORA_TEST_EMAIL_A/B` |

---

## 9. Файли проєкту

| Файл | Призначення |
|------|-------------|
| `docs/MOBSF_SECURITY_UA.md` | ця інструкція |
| `docs/run_security_tests_st.py` | ST API (Storage, Edge, RLS) |
| `docs/jmeter/HIKORA_JMETER_UA.md` | навантажувальне тестування |
| `supabase/storage_avatars_policies.sql` | RLS для avatars |
| `android/app/src/main/AndroidManifest.xml` | backup, cleartext, permissions |
| `android/app/src/main/res/xml/network_security_config.xml` | лише HTTPS |
| `android/create_release_keystore.ps1` | release keystore для MobSF |
| `android/key.properties.example` | шаблон підпису |

### Вже застосовані безпечні зміни

- `allowBackup="false"`, `fullBackupContent="false"`, cleartext заборонено.
- `minSdk = 29` — лише Android 10+ (знімає MobSF про Android 7).
- `ProfileInstallReceiver` видалено з merged manifest.
- Дозволи з коментарями + `uses-feature` (GPS/камера не обов’язкові для встановлення на планшетах без GPS).
- Release signing через `key.properties` (скрипт `create_release_keystore.ps1`).

**Залишаються у MobSF як пояснення, не як баг застосунку:** anon key Supabase; CODE external/temp/logs/clipboard у **фреймворку**; дозволи CAMERA/LOCATION — §5.1.
