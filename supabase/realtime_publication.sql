-- Увімкнути Realtime для групових походів і чату.
-- Виконайте в Supabase → SQL Editor (один раз на проєкт).

ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE trip_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE trips;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
