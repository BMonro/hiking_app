-- =============================================================================
-- Автоматичне нарахування досягнень (Supabase → SQL Editor)
-- =============================================================================
-- Перевіряє умови з таблиці achievements після змін у журналі, маршрутах
-- та оцінках. Записує user_achievements і сповіщення type = 'achievement'.
--
-- Повторний запуск безпечний (idempotent).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Статистика користувача для умов досягнень
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.achievement_user_stats(p_user_id UUID)
RETURNS TABLE (
  hikes_count BIGINT,
  distance_km NUMERIC,
  ascent_m BIGINT,
  routes_created BIGINT,
  ratings_given BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    COUNT(j.id)::BIGINT,
    COALESCE(SUM(j.actual_distance_km), 0)::NUMERIC,
    COALESCE(SUM(j.actual_ascent_m), 0)::BIGINT,
    (SELECT COUNT(*)::BIGINT FROM routes r WHERE r.author_id = p_user_id),
    (SELECT COUNT(*)::BIGINT FROM route_ratings rr WHERE rr.user_id = p_user_id)
  FROM journal_entries j
  WHERE j.user_id = p_user_id;
$$;

-- ---------------------------------------------------------------------------
-- Перевірка та видача нових досягнень (повертає кількість нових)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_and_grant_achievements(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  s RECORD;
  ach RECORD;
  v_current NUMERIC;
  v_granted INTEGER := 0;
  v_inserted INTEGER;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN 0;
  END IF;

  SELECT * INTO s FROM public.achievement_user_stats(p_user_id);

  FOR ach IN
    SELECT a.id, a.code, a.title, a.description, a.condition_type, a.condition_value
    FROM achievements a
    WHERE NOT EXISTS (
      SELECT 1
      FROM user_achievements ua
      WHERE ua.user_id = p_user_id
        AND ua.achievement_id = a.id
    )
  LOOP
    v_current := CASE ach.condition_type
      WHEN 'hikes_count' THEN s.hikes_count::NUMERIC
      WHEN 'distance_km' THEN s.distance_km
      WHEN 'ascent_m' THEN s.ascent_m::NUMERIC
      WHEN 'routes_created' THEN s.routes_created::NUMERIC
      WHEN 'rating_given' THEN s.ratings_given::NUMERIC
      ELSE NULL
    END;

    IF v_current IS NULL OR v_current < ach.condition_value THEN
      CONTINUE;
    END IF;

    INSERT INTO user_achievements (user_id, achievement_id)
    SELECT p_user_id, ach.id
    WHERE NOT EXISTS (
      SELECT 1
      FROM user_achievements ua
      WHERE ua.user_id = p_user_id
        AND ua.achievement_id = ach.id
    );

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    IF v_inserted > 0 THEN
      v_granted := v_granted + 1;

      INSERT INTO notifications (user_id, type, title, body, payload)
      VALUES (
        p_user_id,
        'achievement',
        ach.title,
        COALESCE(ach.description, 'Ви отримали нове досягнення!'),
        jsonb_build_object(
          'achievement_id', ach.id,
          'code', ach.code
        )
      );
    END IF;
  END LOOP;

  RETURN v_granted;
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC для клієнта: синхронізувати досягнення поточного користувача
-- (корисно для уже наявних записів у журналі до встановлення тригерів)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_my_achievements()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  RETURN public.check_and_grant_achievements(uid);
END;
$$;

-- ---------------------------------------------------------------------------
-- Тригери
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_achievements_after_journal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.check_and_grant_achievements(OLD.user_id);
    RETURN OLD;
  END IF;

  PERFORM public.check_and_grant_achievements(NEW.user_id);

  IF TG_OP = 'UPDATE' AND OLD.user_id IS DISTINCT FROM NEW.user_id THEN
    PERFORM public.check_and_grant_achievements(OLD.user_id);
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_achievements_after_route()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.author_id IS NOT NULL THEN
    PERFORM public.check_and_grant_achievements(NEW.author_id);
  ELSIF TG_OP = 'DELETE' AND OLD.author_id IS NOT NULL THEN
    PERFORM public.check_and_grant_achievements(OLD.author_id);
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.author_id IS NOT NULL AND OLD.author_id IS DISTINCT FROM NEW.author_id THEN
      PERFORM public.check_and_grant_achievements(OLD.author_id);
    END IF;
    IF NEW.author_id IS NOT NULL THEN
      PERFORM public.check_and_grant_achievements(NEW.author_id);
    END IF;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_achievements_after_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.check_and_grant_achievements(OLD.user_id);
    RETURN OLD;
  END IF;

  PERFORM public.check_and_grant_achievements(NEW.user_id);

  IF TG_OP = 'UPDATE' AND OLD.user_id IS DISTINCT FROM NEW.user_id THEN
    PERFORM public.check_and_grant_achievements(OLD.user_id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS achievements_journal_entries ON journal_entries;
CREATE TRIGGER achievements_journal_entries
  AFTER INSERT OR UPDATE OR DELETE ON journal_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_achievements_after_journal();

DROP TRIGGER IF EXISTS achievements_routes ON routes;
CREATE TRIGGER achievements_routes
  AFTER INSERT OR UPDATE OR DELETE ON routes
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_achievements_after_route();

DROP TRIGGER IF EXISTS achievements_route_ratings ON route_ratings;
CREATE TRIGGER achievements_route_ratings
  AFTER INSERT OR UPDATE OR DELETE ON route_ratings
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_achievements_after_rating();

-- ---------------------------------------------------------------------------
-- Дозволи для виклику sync з застосунку
-- ---------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.sync_my_achievements() TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_grant_achievements(UUID) TO service_role;

-- Одноразова синхронізація для всіх користувачів (опційно, виконати вручну):
-- DO $$ DECLARE r RECORD; BEGIN
--   FOR r IN SELECT id FROM auth.users LOOP
--     PERFORM public.check_and_grant_achievements(r.id);
--   END LOOP;
-- END $$;
