-- Організатор автоматично стає approved-учасником нового походу.
-- Виконати в Supabase → SQL Editor (можна прибрати upsert з Flutter після цього).

CREATE OR REPLACE FUNCTION public.trg_trip_add_organizer_participant()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.organizer_id IS NOT NULL THEN
    INSERT INTO trip_participants (trip_id, user_id, status)
    VALUES (NEW.id, NEW.organizer_id, 'approved')
    ON CONFLICT (trip_id, user_id) DO UPDATE
      SET status = 'approved';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trip_organizer_participant ON trips;
CREATE TRIGGER trip_organizer_participant
  AFTER INSERT ON trips
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_trip_add_organizer_participant();
