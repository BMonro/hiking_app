-- Базовий профіль для групових походів (чат, заявки, прев’ю учасника).
-- Виконайте в Supabase → SQL Editor, якщо прев’ю показує лише свій профіль.

DROP POLICY IF EXISTS "Authenticated read profiles for trips" ON profiles;

CREATE POLICY "Authenticated read profiles for trips"
ON profiles FOR SELECT
TO authenticated
USING (auth.uid() IS NOT NULL);
