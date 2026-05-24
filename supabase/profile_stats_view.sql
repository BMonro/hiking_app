-- VIEW profile_stats для клієнта (журнал + RLS на journal_entries).
-- Виконати в Supabase SQL Editor, якщо статистика в застосунку порожня.

DROP VIEW IF EXISTS public.profile_stats;

CREATE VIEW public.profile_stats
WITH (security_invoker = true)
AS
SELECT
  j.user_id,
  COUNT(j.id)::bigint AS total_hikes,
  COALESCE(SUM(j.actual_distance_km), 0)::numeric AS total_distance_km,
  COALESCE(SUM(j.actual_ascent_m), 0)::bigint AS total_ascent_m
FROM public.journal_entries j
GROUP BY j.user_id;

GRANT SELECT ON public.profile_stats TO authenticated;
