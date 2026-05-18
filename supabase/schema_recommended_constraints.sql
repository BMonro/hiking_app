-- Рекомендовані обмеження для логіки застосунку та seed/досягнень.
-- Виконати один раз у SQL Editor (безпечно повторювати).

-- Одна оцінка користувача на маршрут
CREATE UNIQUE INDEX IF NOT EXISTS route_ratings_user_route_unique
  ON public.route_ratings (user_id, route_id);

-- Одне досягнення один раз на користувача
CREATE UNIQUE INDEX IF NOT EXISTS user_achievements_user_achievement_unique
  ON public.user_achievements (user_id, achievement_id);

-- Одна умова здоровʼя без дублікатів
CREATE UNIQUE INDEX IF NOT EXISTS profile_health_conditions_user_condition_unique
  ON public.profile_health_conditions (user_id, condition);
