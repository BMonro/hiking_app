-- Синхронізація profiles.experience_count з кількістю записів у журналі.
-- Виконати в Supabase → SQL Editor.

CREATE OR REPLACE FUNCTION public.sync_profile_experience_count(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  IF p_user_id IS NULL THEN RETURN;
  END IF;

  SELECT COUNT(*)::INTEGER INTO v_count
  FROM journal_entries
  WHERE user_id = p_user_id;

  UPDATE profiles
  SET experience_count = v_count,
      updated_at = now()
  WHERE id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_sync_experience_after_journal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.sync_profile_experience_count(OLD.user_id);
    RETURN OLD;
  END IF;

  PERFORM public.sync_profile_experience_count(NEW.user_id);

  IF TG_OP = 'UPDATE' AND OLD.user_id IS DISTINCT FROM NEW.user_id THEN
    PERFORM public.sync_profile_experience_count(OLD.user_id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS journal_sync_experience_count ON journal_entries;
CREATE TRIGGER journal_sync_experience_count
  AFTER INSERT OR UPDATE OR DELETE ON journal_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_sync_experience_after_journal();

-- Одноразово для всіх користувачів:
-- DO $$ DECLARE r RECORD; BEGIN
--   FOR r IN SELECT id FROM auth.users LOOP
--     PERFORM public.sync_profile_experience_count(r.id);
--   END LOOP;
-- END $$;
