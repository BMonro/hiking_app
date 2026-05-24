-- Сповіщення про нові повідомлення в чаті походу (type = new_message).
-- Edge Function trip-chat вставляє рядки через service role.
-- Виконайте в Supabase → SQL Editor, якщо CHECK на notifications.type ще без new_message.

-- Розширити дозволені типи (якщо обмеження вже є — пропустіть або адаптуйте):
-- ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
-- ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
--   CHECK (type IN (
--     'trip_request', 'trip_approved', 'trip_rejected',
--     'new_message', 'achievement'
--   ));

-- Realtime для чату (якщо ще не виконували realtime_publication.sql):
-- ALTER PUBLICATION supabase_realtime ADD TABLE messages;
