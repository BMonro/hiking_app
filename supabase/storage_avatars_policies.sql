
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

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
  )
  WITH CHECK (
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
