-- ============================================================
--  HOLO-FIT — Supabase PostgreSQL Schema
--  Ejecutar en orden dentro del SQL Editor de Supabase
-- ============================================================

-- Habilitar extensión para UUIDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 1. PROFILES
-- Extiende auth.users de Supabase con datos del onboarding
-- ============================================================
CREATE TABLE public.profiles (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_user_id     UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  username         TEXT UNIQUE,
  full_name        TEXT,
  avatar_url       TEXT,
  -- Resultado del cuestionario Smart Onboarding
  fitness_level    TEXT CHECK (fitness_level IN ('beginner','intermediate','advanced')),
  onboarding_data  JSONB DEFAULT '{}',
  -- Economía de Holo-Coins
  holo_coins       INT NOT NULL DEFAULT 0 CHECK (holo_coins >= 0),
  total_workouts   INT NOT NULL DEFAULT 0,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON COLUMN public.profiles.onboarding_data IS
  'Respuestas crudas del cuestionario: {bio, objetivo, logistica, limitaciones}';

-- ============================================================
-- 2. SKINS (Tienda de accesorios del Holo-Tigre)
-- Se crea ANTES de tiger_state por FK
-- ============================================================
CREATE TABLE public.skins (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name              TEXT NOT NULL,
  description       TEXT,
  lottie_json_url   TEXT,                -- URL al JSON de LottieFiles
  preview_image_url TEXT,
  price_coins       INT NOT NULL DEFAULT 0 CHECK (price_coins >= 0),
  price_usd_cents   INT DEFAULT NULL,    -- NULL = solo comprable con coins
  is_premium        BOOLEAN NOT NULL DEFAULT FALSE,
  rarity            TEXT NOT NULL DEFAULT 'common'
                    CHECK (rarity IN ('common','rare','epic','legendary')),
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 3. TIGER_STATE
-- Estado actual de evolución del Holo-Tigre por usuario
-- ============================================================
CREATE TABLE public.tiger_state (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id            UUID NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
  -- Estado de la animación
  current_state         TEXT NOT NULL DEFAULT 'dormant'
                        CHECK (current_state IN ('dormant','active','fire','legendary')),
  evolution_level       INT NOT NULL DEFAULT 1 CHECK (evolution_level BETWEEN 1 AND 5),
  equipped_skin_id      UUID REFERENCES public.skins(id) ON DELETE SET NULL,
  -- Racha
  streak_days           INT NOT NULL DEFAULT 0 CHECK (streak_days >= 0),
  last_activity_at      TIMESTAMPTZ,
  streak_frozen_at      TIMESTAMPTZ,     -- Se setea a las 24h sin actividad
  -- Accesorios desbloqueados (array de skin IDs)
  unlocked_accessories  JSONB NOT NULL DEFAULT '[]',
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON COLUMN public.tiger_state.current_state IS
  'dormant=+48h sin actividad | active=racha activa | fire=racha 7d+ | legendary=racha 30d+';
COMMENT ON COLUMN public.tiger_state.streak_frozen_at IS
  'Se congela a las 24h; si llega a 48h el tigre pasa a dormant';

-- ============================================================
-- 4. EXERCISES (Catálogo maestro de ejercicios)
-- ============================================================
CREATE TABLE public.exercises (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name             TEXT NOT NULL,
  description      TEXT,
  muscle_group     TEXT NOT NULL,
  equipment_needed TEXT NOT NULL DEFAULT 'none',
  sets             INT DEFAULT 3,
  reps             INT DEFAULT 10,
  duration_seconds INT DEFAULT NULL,   -- Para ejercicios por tiempo (planchas, etc.)
  video_url        TEXT,
  tags             TEXT[] NOT NULL DEFAULT '{}',  -- Para el Logic Engine
  is_active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_exercises_tags ON public.exercises USING GIN(tags);
CREATE INDEX idx_exercises_muscle ON public.exercises(muscle_group);

-- ============================================================
-- 5. ROUTINES (Plantillas de rutinas predefinidas)
-- ============================================================
CREATE TABLE public.routines (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name             TEXT NOT NULL,
  description      TEXT,
  difficulty       TEXT NOT NULL CHECK (difficulty IN ('beginner','intermediate','advanced')),
  target_tags      TEXT[] NOT NULL DEFAULT '{}', -- Etiquetas del onboarding que activan esta rutina
  duration_minutes INT NOT NULL DEFAULT 45,
  is_active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_routines_tags ON public.routines USING GIN(target_tags);

-- ============================================================
-- 6. ROUTINE_EXERCISES (Tabla de unión: ejercicios en rutinas)
-- ============================================================
CREATE TABLE public.routine_exercises (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  routine_id     UUID NOT NULL REFERENCES public.routines(id) ON DELETE CASCADE,
  exercise_id    UUID NOT NULL REFERENCES public.exercises(id) ON DELETE CASCADE,
  order_index    INT NOT NULL DEFAULT 0,
  sets_override  INT DEFAULT NULL,   -- Sobrescribe el default del ejercicio
  reps_override  INT DEFAULT NULL,
  UNIQUE (routine_id, exercise_id)
);

CREATE INDEX idx_re_routine ON public.routine_exercises(routine_id);

-- ============================================================
-- 7. USER_ROUTINES (Rutinas asignadas al usuario por el Planner)
-- ============================================================
CREATE TABLE public.user_routines (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  routine_id     UUID NOT NULL REFERENCES public.routines(id),
  assigned_date  DATE NOT NULL DEFAULT CURRENT_DATE,
  is_completed   BOOLEAN NOT NULL DEFAULT FALSE,
  completed_at   TIMESTAMPTZ DEFAULT NULL,
  coins_earned   INT NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (profile_id, assigned_date)  -- Una rutina por día por usuario
);

CREATE INDEX idx_ur_profile ON public.user_routines(profile_id);
CREATE INDEX idx_ur_date    ON public.user_routines(assigned_date);

-- ============================================================
-- 8. WORKOUT_LOGS (Registro detallado de cada entrenamiento)
-- ============================================================
CREATE TABLE public.workout_logs (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  user_routine_id  UUID REFERENCES public.user_routines(id) ON DELETE SET NULL,
  started_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at      TIMESTAMPTZ,
  duration_minutes INT,
  coins_earned     INT NOT NULL DEFAULT 0,
  -- Snapshot de ejercicios completados: [{exercise_id, sets_done, reps_done, notes}]
  exercises_done   JSONB NOT NULL DEFAULT '[]',
  notes            TEXT
);

CREATE INDEX idx_wl_profile ON public.workout_logs(profile_id);
CREATE INDEX idx_wl_started ON public.workout_logs(started_at);

-- ============================================================
-- 9. STREAKS (Historial diario de actividad para la racha)
-- ============================================================
CREATE TABLE public.streaks (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id            UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  streak_date           DATE NOT NULL DEFAULT CURRENT_DATE,
  was_active            BOOLEAN NOT NULL DEFAULT FALSE,
  streak_count_at_day   INT NOT NULL DEFAULT 0,
  UNIQUE (profile_id, streak_date)
);

CREATE INDEX idx_streaks_profile ON public.streaks(profile_id, streak_date DESC);

-- ============================================================
-- 10. MILESTONES (Hitos del sistema de gamificación)
-- ============================================================
CREATE TABLE public.milestones (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name            TEXT NOT NULL,
  description     TEXT,
  badge_icon_url  TEXT,
  -- Qué dispara el hito
  trigger_type    TEXT NOT NULL CHECK (trigger_type IN (
                    'streak_days','total_workouts','coins_earned',
                    'evolution_level','first_login','skin_purchased'
                  )),
  trigger_value   INT NOT NULL DEFAULT 1,
  coins_reward    INT NOT NULL DEFAULT 0,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 11. USER_MILESTONES (Hitos desbloqueados por usuario)
-- ============================================================
CREATE TABLE public.user_milestones (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  milestone_id  UUID NOT NULL REFERENCES public.milestones(id),
  unlocked_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (profile_id, milestone_id)
);

CREATE INDEX idx_um_profile ON public.user_milestones(profile_id);

-- ============================================================
-- 12. SKIN_PURCHASES (Compras en la tienda de skins)
-- ============================================================
CREATE TABLE public.skin_purchases (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  skin_id            UUID NOT NULL REFERENCES public.skins(id),
  payment_method     TEXT NOT NULL CHECK (payment_method IN ('holo_coins','stripe')),
  stripe_payment_id  TEXT DEFAULT NULL,  -- ID de Stripe si es pago real
  coins_spent        INT NOT NULL DEFAULT 0,
  purchased_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (profile_id, skin_id)  -- No comprar la misma skin dos veces
);

CREATE INDEX idx_sp_profile ON public.skin_purchases(profile_id);

-- ============================================================
-- TRIGGERS Y FUNCIONES AUXILIARES
-- ============================================================

-- Auto-actualizar updated_at en profiles
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER tiger_state_updated_at
  BEFORE UPDATE ON public.tiger_state
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Auto-crear profile + tiger_state al registrar usuario en auth.users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  new_profile_id UUID;
BEGIN
  INSERT INTO public.profiles (auth_user_id, username, full_name, avatar_url)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'username',
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'avatar_url'
  )
  RETURNING id INTO new_profile_id;

  INSERT INTO public.tiger_state (profile_id)
  VALUES (new_profile_id);

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Función: completar workout → sumar coins + actualizar racha
CREATE OR REPLACE FUNCTION public.complete_workout(
  p_user_routine_id UUID,
  p_exercises_done  JSONB DEFAULT '[]',
  p_notes           TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_profile_id    UUID;
  v_coins_earned  INT := 50;  -- Base coins por workout completado
  v_workout_log   UUID;
  v_streak        INT;
BEGIN
  -- Obtener profile desde user_routine
  SELECT profile_id INTO v_profile_id
  FROM public.user_routines WHERE id = p_user_routine_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'user_routine not found');
  END IF;

  -- Marcar rutina como completada
  UPDATE public.user_routines
  SET is_completed = TRUE, completed_at = NOW(), coins_earned = v_coins_earned
  WHERE id = p_user_routine_id;

  -- Crear workout log
  INSERT INTO public.workout_logs
    (profile_id, user_routine_id, finished_at, coins_earned, exercises_done, notes)
  VALUES
    (v_profile_id, p_user_routine_id, NOW(), v_coins_earned, p_exercises_done, p_notes)
  RETURNING id INTO v_workout_log;

  -- Actualizar coins y total_workouts en profile
  UPDATE public.profiles
  SET holo_coins    = holo_coins + v_coins_earned,
      total_workouts = total_workouts + 1
  WHERE id = v_profile_id;

  -- Actualizar streak diario
  INSERT INTO public.streaks (profile_id, streak_date, was_active, streak_count_at_day)
  VALUES (v_profile_id, CURRENT_DATE, TRUE, 1)
  ON CONFLICT (profile_id, streak_date)
  DO UPDATE SET was_active = TRUE;

  -- Recalcular streak_days en tiger_state
  WITH consecutive AS (
    SELECT streak_date,
           ROW_NUMBER() OVER (ORDER BY streak_date DESC) AS rn
    FROM public.streaks
    WHERE profile_id = v_profile_id AND was_active = TRUE
  ),
  groups AS (
    SELECT streak_date - (rn || ' days')::INTERVAL AS grp
    FROM consecutive
  )
  SELECT COUNT(*) INTO v_streak
  FROM groups
  WHERE grp = (SELECT grp FROM groups ORDER BY grp DESC LIMIT 1);

  -- Actualizar tiger_state según la racha
  UPDATE public.tiger_state
  SET streak_days       = v_streak,
      last_activity_at  = NOW(),
      streak_frozen_at  = NULL,
      current_state     = CASE
                            WHEN v_streak >= 30 THEN 'legendary'
                            WHEN v_streak >= 7  THEN 'fire'
                            ELSE 'active'
                          END,
      evolution_level   = LEAST(5, 1 + (v_streak / 10))
  WHERE profile_id = v_profile_id;

  RETURN jsonb_build_object(
    'success',      TRUE,
    'workout_log',  v_workout_log,
    'coins_earned', v_coins_earned,
    'streak_days',  v_streak
  );
END;
$$;

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================
ALTER TABLE public.profiles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tiger_state    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_routines  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_logs   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.streaks        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.skin_purchases  ENABLE ROW LEVEL SECURITY;

-- Usuarios solo ven y editan sus propios datos
CREATE POLICY "own profile" ON public.profiles
  FOR ALL USING (auth.uid() = auth_user_id);

CREATE POLICY "own tiger" ON public.tiger_state
  FOR ALL USING (profile_id = (SELECT id FROM public.profiles WHERE auth_user_id = auth.uid()));

CREATE POLICY "own routines" ON public.user_routines
  FOR ALL USING (profile_id = (SELECT id FROM public.profiles WHERE auth_user_id = auth.uid()));

CREATE POLICY "own logs" ON public.workout_logs
  FOR ALL USING (profile_id = (SELECT id FROM public.profiles WHERE auth_user_id = auth.uid()));

CREATE POLICY "own streaks" ON public.streaks
  FOR ALL USING (profile_id = (SELECT id FROM public.profiles WHERE auth_user_id = auth.uid()));

CREATE POLICY "own milestones" ON public.user_milestones
  FOR ALL USING (profile_id = (SELECT id FROM public.profiles WHERE auth_user_id = auth.uid()));

CREATE POLICY "own purchases" ON public.skin_purchases
  FOR ALL USING (profile_id = (SELECT id FROM public.profiles WHERE auth_user_id = auth.uid()));

-- Catálogos públicos (lectura)
ALTER TABLE public.exercises  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routines   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.skins      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.milestones ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public read exercises"  ON public.exercises  FOR SELECT USING (is_active = TRUE);
CREATE POLICY "public read routines"   ON public.routines   FOR SELECT USING (is_active = TRUE);
CREATE POLICY "public read skins"      ON public.skins      FOR SELECT USING (is_active = TRUE);
CREATE POLICY "public read milestones" ON public.milestones FOR SELECT USING (is_active = TRUE);

-- ============================================================
-- DATOS SEED — Hitos iniciales
-- ============================================================
INSERT INTO public.milestones (name, description, trigger_type, trigger_value, coins_reward) VALUES
  ('Primer Rugido',      'Completa tu primer entrenamiento',        'total_workouts', 1,   100),
  ('Racha de Fuego',     'Mantén 7 días consecutivos de actividad', 'streak_days',    7,   250),
  ('Imparable',          'Alcanza 30 días de racha',                'streak_days',    30,  1000),
  ('Veterano',           'Completa 50 entrenamientos',              'total_workouts', 50,  500),
  ('Tigre de Leyenda',   'Alcanza nivel de evolución 5',            'evolution_level',5,   750),
  ('Primer Accesorio',   'Compra tu primera skin en la tienda',     'skin_purchased', 1,   50);
