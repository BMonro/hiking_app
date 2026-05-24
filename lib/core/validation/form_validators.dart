
abstract final class FormValidators {
  static final RegExp _emailPattern = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  static String trim(String? value) => (value ?? '').trim();

  static String? required(String? value, {String message = 'Обов\'язкове поле'}) {
    if (trim(value).isEmpty) return message;
    return null;
  }

  static String? email(String? value, {bool requiredField = true}) {
    final v = trim(value);
    if (v.isEmpty) {
      return requiredField ? 'Заповніть email' : null;
    }
    if (!_emailPattern.hasMatch(v)) {
      return 'Введіть коректну електронну пошту';
    }
    return null;
  }

  static String? password(String? value, {int minLength = 6}) {
    final v = value ?? '';
    if (v.isEmpty) return 'Заповніть пароль';
    if (v.length < minLength) return 'Мінімум $minLength символів';
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    final v = value ?? '';
    if (v.isEmpty) return 'Підтвердіть пароль';
    if (v != password) return 'Паролі не співпадають';
    return null;
  }

  static String? personName(String? value, {required String fieldLabel}) {
    final v = trim(value);
    if (v.isEmpty) return 'Заповніть $fieldLabel';
    if (v.length < 2) return '$fieldLabel: мінімум 2 символи';
    if (v.length > 60) return '$fieldLabel: занадто довге';
    return null;
  }

  static String? fullName(String? value) {
    final v = trim(value);
    if (v.isEmpty) return 'Введіть ім\'я та прізвище';
    if (v.length < 3) return 'Мінімум 3 символи';
    if (v.length > 120) return 'Занадто довге ім\'я';
    return null;
  }

  static String? title(String? value) {
    final v = trim(value);
    if (v.isEmpty) return 'Введіть назву';
    if (v.length > 200) return 'Назва: максимум 200 символів';
    return null;
  }

  static String? description(String? value, {bool requiredField = false}) {
    final v = trim(value);
    if (requiredField && v.isEmpty) return 'Додайте опис';
    if (v.length > 5000) return 'Опис: максимум 5000 символів';
    return null;
  }

  static String? meetingPoint(String? value) {
    final v = trim(value);
    if (v.isEmpty) return 'Вкажіть місце збору';
    if (v.length > 300) return 'Занадто довгий опис місця';
    return null;
  }

  static String? age(String? value, {bool requiredField = false}) {
    final v = trim(value);
    if (v.isEmpty) return requiredField ? 'Вкажіть вік' : null;
    final n = int.tryParse(v);
    if (n == null || n <= 0 || n >= 120) {
      return 'Вкажіть коректний вік (1–119)';
    }
    return null;
  }

  static String? optionalNonNegativeInt(
    String? value, {
    String field = 'Значення',
    int max = 999999,
  }) {
    final v = trim(value);
    if (v.isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null || n < 0) return '$field: введіть ціле число ≥ 0';
    if (n > max) return '$field: максимум $max';
    return null;
  }

  static String? positiveInt(
    String? value, {
    required String field,
    int min = 1,
    int max = 999,
  }) {
    final v = trim(value);
    if (v.isEmpty) return 'Заповніть $field';
    final n = int.tryParse(v);
    if (n == null || n < min || n > max) {
      return '$field: від $min до $max';
    }
    return null;
  }

  static String? groupMaxMembers(String? value) {
    return positiveInt(value, field: 'Кількість осіб', min: 2, max: 100);
  }

  static String? optionalDecimal(
    String? value, {
    String field = 'Значення',
    double min = 0,
    double max = 99999,
  }) {
    final v = trim(value).replaceAll(',', '.');
    if (v.isEmpty) return null;
    final n = double.tryParse(v);
    if (n == null || n < min || n > max) {
      return '$field: число від $min до $max';
    }
    return null;
  }

  static String? latitude(String? value, {bool requiredField = true}) {
    final v = trim(value).replaceAll(',', '.');
    if (v.isEmpty) return requiredField ? 'Вкажіть широту' : null;
    final n = double.tryParse(v);
    if (n == null || n < -90 || n > 90) return 'Широта: від -90 до 90';
    return null;
  }

  static String? longitude(String? value, {bool requiredField = true}) {
    final v = trim(value).replaceAll(',', '.');
    if (v.isEmpty) return requiredField ? 'Вкажіть довготу' : null;
    final n = double.tryParse(v);
    if (n == null || n < -180 || n > 180) return 'Довгота: від -180 до 180';
    return null;
  }

  static String? optionalAltitude(String? value) {
    return optionalNonNegativeInt(value, field: 'Висота', max: 9000);
  }

  static String? pointName(String? value, {bool requiredField = false}) {
    final v = trim(value);
    if (v.isEmpty) {
      return requiredField ? 'Вкажіть назву точки' : null;
    }
    if (v.length > 120) return 'Назва точки: максимум 120 символів';
    return null;
  }

  static String? searchQuery(String? value, {int maxLen = 120}) {
    final v = trim(value);
    if (v.length > maxLen) return 'Занадто довгий запит (макс. $maxLen)';
    return null;
  }

  static String? chatMessage(String? value) {
    final v = trim(value);
    if (v.isEmpty) return 'Введіть повідомлення';
    if (v.length > 2000) return 'Повідомлення занадто довге (макс. 2000)';
    return null;
  }

  static String? aiPrompt(String? value) {
    final v = trim(value);
    if (v.isEmpty) return 'Введіть запит';
    if (v.length > 4000) return 'Запит занадто довгий';
    return null;
  }

  static String? filterMaxDuration(String? value) {
    return optionalDecimal(value, field: 'Тривалість', min: 0, max: 720);
  }

  static String? filterMaxAscent(String? value) {
    return optionalNonNegativeInt(value, field: 'Перепад висот', max: 10000);
  }

  static String? journalDistance(String? value) =>
      optionalDecimal(value, field: 'Відстань', min: 0, max: 5000);

  static String? journalDuration(String? value) =>
      optionalDecimal(value, field: 'Тривалість', min: 0, max: 720);

  static String? journalAscent(String? value) =>
      optionalNonNegativeInt(value, field: 'Перепад висот', max: 15000);

  static String? notes(String? value) {
    if ((value ?? '').length > 5000) {
      return 'Нотатки: максимум 5000 символів';
    }
    return null;
  }

  static String? bio(String? value) {
    if (trim(value).length > 1000) {
      return 'Про себе: максимум 1000 символів';
    }
    return null;
  }

  static String? reviewComment(String? value) {
    final v = trim(value);
    if (v.length > 1000) return 'Відгук: максимум 1000 символів';
    return null;
  }

  static String? optionalPhone(String? value) {
    final v = trim(value);
    if (v.isEmpty) return null;
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9 || digits.length > 15) {
      return 'Введіть коректний номер телефону';
    }
    if (v.length > 20) return 'Номер занадто довгий';
    return null;
  }

  static String? healthConditions(String? value) {
    if (trim(value).length > 500) return 'Занадто довгий текст';
    return null;
  }

  static String? experienceText(String? value) {
    if (trim(value).length > 500) return 'Занадто довгий опис досвіду';
    return null;
  }
}
