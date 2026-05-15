-- Виконайте в Supabase SQL Editor (або як міграцію), якщо бакет уже створено:
-- Dashboard → Storage → New bucket → назва: avatars → увімкніть Public, якщо потрібні getPublicUrl-посилання.

-- Політики для bucket avatars (ім’я файлу в застосунку: {auth.uid()}-avatar-{timestamp}.jpg)

DROP POLICY IF EXISTS "avatars_public_read" ON storage.objects;
DROP POLICY IF EXISTS "avatars_authenticated_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "avatars_authenticated_update_own" ON storage.objects;
DROP POLICY IF EXISTS "avatars_authenticated_delete_own" ON storage.objects;

CREATE POLICY "avatars_public_read"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'avatars');

CREATE POLICY "avatars_authenticated_insert_own"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND name LIKE auth.uid()::text || '-%'
  );

CREATE POLICY "avatars_authenticated_update_own"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND name LIKE auth.uid()::text || '-%'
  );

CREATE POLICY "avatars_authenticated_delete_own"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'avatars'
    AND name LIKE auth.uid()::text || '-%'
  );
