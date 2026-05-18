import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Завантаження аватарів у Supabase Storage (bucket `avatars`).
class AvatarStorageService {
  AvatarStorageService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const bucket = 'avatars';

  final SupabaseClient _client;

  /// Шлях у бакеті: `{userId}-avatar.jpg` (відповідає RLS `uid-%`).
  static String objectPath(String userId) => '$userId-avatar.jpg';

  /// Public URL після успішного upload.
  Future<String> uploadAvatar({
    required String userId,
    required File imageFile,
  }) async {
    final bytes = await imageFile.readAsBytes();
    if (bytes.isEmpty) {
      throw const AvatarUploadException('Файл порожній');
    }

    final path = objectPath(userId);
    try {
      await _client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
    } on StorageException catch (e) {
      throw AvatarUploadException(_friendlyMessage(e));
    }

    final baseUrl = _client.storage.from(bucket).getPublicUrl(path);
    // Оновлення того самого файлу (upsert) — обходимо кеш зображення в UI.
    return '$baseUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  static String _friendlyMessage(StorageException e) {
    final msg = e.message.toLowerCase();
    if (e.statusCode == '403' ||
        msg.contains('row-level security') ||
        msg.contains('policy')) {
      return 'Немає доступу до сховища avatars. У Supabase створіть публічний бакет '
          'і виконайте supabase/storage_avatars_policies.sql';
    }
    if (msg.contains('bucket') && msg.contains('not found')) {
      return 'Бакет «avatars» не знайдено. Створіть його в Supabase → Storage.';
    }
    if (msg.contains('already exists')) {
      return 'Файл уже існує — спробуйте ще раз';
    }
    return e.message.isNotEmpty ? e.message : 'Помилка завантаження (${e.statusCode})';
  }
}

class AvatarUploadException implements Exception {
  final String message;
  const AvatarUploadException(this.message);

  @override
  String toString() => message;
}
