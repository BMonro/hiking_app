CREATE TABLE profiles (
  id                   UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name            TEXT,
  avatar_url           TEXT,
  age                  INTEGER CHECK (age > 0 AND age < 120),
  fitness_level        TEXT CHECK (fitness_level IN ('beginner','intermediate','advanced')) DEFAULT 'beginner',
  experience_count     INTEGER DEFAULT 0,
  preferred_difficulty TEXT CHECK (preferred_difficulty IN ('easy','medium','hard')),
  preferred_duration_h NUMERIC,
  bio                  TEXT,
  updated_at           TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE profile_health_conditions (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  condition TEXT NOT NULL,
  UNIQUE (user_id, condition)
);

CREATE TABLE routes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  title           TEXT NOT NULL,
  region          TEXT,
  difficulty      TEXT CHECK (difficulty IN ('easy','medium','hard')) DEFAULT 'easy',
  route_type      TEXT CHECK (route_type IN ('circular', 'linear', 'radial', 'combined')) DEFAULT 'linear',
  distance_km     NUMERIC(6,2),
  ascent_m        INTEGER,
  duration_h      NUMERIC(5,1),
  description     TEXT,
  cover_image_url TEXT,
  geojson         JSONB,
  is_public       BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE route_points (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  route_id    UUID REFERENCES routes(id) ON DELETE CASCADE,
  name        TEXT,
  latitude    NUMERIC NOT NULL,
  longitude   NUMERIC NOT NULL,
  altitude_m  INTEGER,
  point_type  TEXT CHECK (point_type IN
              ('start','finish','peak','water','shelter','danger','viewpoint')),
  description TEXT,
  sort_order  INTEGER DEFAULT 0
);

CREATE TABLE public.route_ratings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  route_id UUID NOT NULL REFERENCES public.routes(id) ON DELETE CASCADE,
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE saved_routes (
  user_id  UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  route_id UUID REFERENCES routes(id) ON DELETE CASCADE,
  saved_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, route_id)
);

CREATE TABLE offline_routes (
  user_id       UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  route_id      UUID REFERENCES routes(id) ON DELETE CASCADE,
  downloaded_at TIMESTAMPTZ DEFAULT now(),
  tile_cache_mb NUMERIC,
  PRIMARY KEY (user_id, route_id)
);

CREATE TABLE trips (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  route_id      UUID REFERENCES routes(id) ON DELETE SET NULL,
  organizer_id  UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  title         TEXT NOT NULL,
  description   TEXT,
  start_date    DATE NOT NULL,
  end_date      DATE NOT NULL,
  meeting_point TEXT,
  max_members   INTEGER DEFAULT 10,
  status        TEXT CHECK (status IN
                ('open','closed','completed','cancelled')) DEFAULT 'open',
  trip_code     TEXT UNIQUE,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE trip_participants (
  trip_id    UUID REFERENCES trips(id) ON DELETE CASCADE,
  user_id    UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  status     TEXT CHECK (status IN ('pending','approved','rejected')) DEFAULT 'pending',
  applied_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (trip_id, user_id)
);

CREATE TABLE messages (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id   UUID REFERENCES trips(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  content   TEXT NOT NULL,
  sent_at   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE journal_entries (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  route_id           UUID REFERENCES routes(id) ON DELETE SET NULL,
  trip_id            UUID REFERENCES trips(id) ON DELETE SET NULL,
  title              TEXT,
  date               DATE NOT NULL,
  notes              TEXT,
  actual_distance_km NUMERIC,
  actual_duration_h  NUMERIC,
  actual_ascent_m    INTEGER,
  weather_summary    TEXT,
  created_at         TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE journal_photos (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id    UUID REFERENCES journal_entries(id) ON DELETE CASCADE,
  photo_url   TEXT NOT NULL,
  uploaded_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE achievements (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code            TEXT UNIQUE NOT NULL,
  title           TEXT NOT NULL,
  description     TEXT,
  icon_url        TEXT,
  condition_type  TEXT CHECK (condition_type IN
                  ('hikes_count','distance_km','ascent_m','routes_created','rating_given')),
  condition_value INTEGER NOT NULL
);

CREATE TABLE user_achievements (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  achievement_id UUID REFERENCES achievements(id) ON DELETE CASCADE,
  earned_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, achievement_id)
);

CREATE TABLE notifications (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  type       TEXT CHECK (type IN
             ('trip_request','trip_approved','trip_rejected','new_message','achievement')),
  title      TEXT NOT NULL,
  body       TEXT,
  is_read    BOOLEAN DEFAULT false,
  payload    JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE VIEW profile_stats AS
SELECT
  u.id                                       AS user_id,
  COUNT(j.id)                                AS total_hikes,
  COALESCE(SUM(j.actual_distance_km), 0)     AS total_distance_km,
  COALESCE(SUM(j.actual_ascent_m), 0)        AS total_ascent_m
FROM auth.users u
LEFT JOIN journal_entries j ON j.user_id = u.id
GROUP BY u.id;

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile_health_conditions ENABLE ROW LEVEL SECURITY;
ALTER TABLE routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE route_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE route_ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE offline_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Own profile read"   ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Own profile insert" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Own profile update" ON profiles FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Own conditions" ON profile_health_conditions FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Public routes read"      ON routes FOR SELECT USING (is_public = true OR auth.uid() = author_id);
CREATE POLICY "Auth users create route" ON routes FOR INSERT WITH CHECK (auth.uid() = author_id);
CREATE POLICY "Author updates route"    ON routes FOR UPDATE USING (auth.uid() = author_id);
CREATE POLICY "Author deletes route"    ON routes FOR DELETE USING (auth.uid() = author_id);

CREATE POLICY "Route points read"     ON route_points FOR SELECT USING (true);
CREATE POLICY "Author manages points" ON route_points FOR ALL USING (
  EXISTS (SELECT 1 FROM routes WHERE routes.id = route_points.route_id AND routes.author_id = auth.uid())
);

CREATE POLICY "Ratings read"       ON route_ratings FOR SELECT USING (true);
CREATE POLICY "Own rating insert"  ON route_ratings FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Own rating update"  ON route_ratings FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Own saved routes" ON saved_routes FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Own offline routes" ON offline_routes FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Public trips read"       ON trips FOR SELECT USING (true);
CREATE POLICY "Auth users create trips" ON trips FOR INSERT WITH CHECK (auth.uid() = organizer_id);
CREATE POLICY "Organizer updates trip"  ON trips FOR UPDATE USING (auth.uid() = organizer_id);
CREATE POLICY "Organizer deletes trip"  ON trips FOR DELETE USING (auth.uid() = organizer_id);

CREATE POLICY "Participants read" ON trip_participants FOR SELECT USING (
  auth.uid() = user_id OR
  EXISTS (SELECT 1 FROM trips WHERE trips.id = trip_participants.trip_id AND trips.organizer_id = auth.uid())
);
CREATE POLICY "User applies"             ON trip_participants FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Organizer manages"        ON trip_participants FOR UPDATE USING (
  EXISTS (SELECT 1 FROM trips WHERE trips.id = trip_participants.trip_id AND trips.organizer_id = auth.uid())
);

CREATE POLICY "Members read messages" ON messages FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM trip_participants
    WHERE trip_participants.trip_id = messages.trip_id
    AND trip_participants.user_id = auth.uid()
    AND trip_participants.status = 'approved'
  ) OR
  EXISTS (SELECT 1 FROM trips WHERE trips.id = messages.trip_id AND trips.organizer_id = auth.uid())
);
CREATE POLICY "Members send messages" ON messages FOR INSERT WITH CHECK (
  auth.uid() = sender_id AND (
    EXISTS (
      SELECT 1 FROM trip_participants
      WHERE trip_participants.trip_id = messages.trip_id
      AND trip_participants.user_id = auth.uid()
      AND trip_participants.status = 'approved'
    ) OR
    EXISTS (SELECT 1 FROM trips WHERE trips.id = messages.trip_id AND trips.organizer_id = auth.uid())
  )
);

ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE trip_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE trips;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

CREATE POLICY "Own journal read"   ON journal_entries FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Own journal insert" ON journal_entries FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Own journal update" ON journal_entries FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Own journal delete" ON journal_entries FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Own photos read" ON journal_photos FOR SELECT USING (
  EXISTS (SELECT 1 FROM journal_entries WHERE journal_entries.id = journal_photos.entry_id AND journal_entries.user_id = auth.uid())
);
CREATE POLICY "Own photos insert" ON journal_photos FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM journal_entries WHERE journal_entries.id = journal_photos.entry_id AND journal_entries.user_id = auth.uid())
);
CREATE POLICY "Own photos delete" ON journal_photos FOR DELETE USING (
  EXISTS (SELECT 1 FROM journal_entries WHERE journal_entries.id = journal_photos.entry_id AND journal_entries.user_id = auth.uid())
);

CREATE POLICY "Achievements read" ON achievements FOR SELECT USING (true);

CREATE POLICY "Own achievements read"  ON user_achievements FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Own achievements insert" ON user_achievements FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Own notifications" ON notifications FOR ALL USING (auth.uid() = user_id);
