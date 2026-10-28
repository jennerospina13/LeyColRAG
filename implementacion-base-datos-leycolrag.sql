-- LeyColRAG: implementación existente del MVP
-- Referencia para entorno NUEVO compatible con Lovable Cloud.
-- No ejecutar de nuevo sobre tablas existentes. No modifica auth.users.
-- Fuente: las dos migraciones originales, reproducidas sin alterar sus sentencias.
-- 2026-10-26: base activa no disponible; ejecución en vivo no verificada.

-- 0000_create_legal_chat_messages.sql
CREATE TABLE public.legal_chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  ai_message_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  parts JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, ai_message_id)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.legal_chat_messages TO authenticated;
GRANT ALL ON public.legal_chat_messages TO service_role;
ALTER TABLE public.legal_chat_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read their legal chat" ON public.legal_chat_messages FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users can add to their legal chat" ON public.legal_chat_messages FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their legal chat" ON public.legal_chat_messages FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their legal chat" ON public.legal_chat_messages FOR DELETE TO authenticated USING (auth.uid() = user_id);
CREATE INDEX legal_chat_messages_user_created_idx ON public.legal_chat_messages (user_id, created_at);

-- 0001_create_profiles.sql
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL DEFAULT '',
  profession TEXT NOT NULL DEFAULT '',
  document_type TEXT NOT NULL DEFAULT 'CC',
  document_number TEXT NOT NULL DEFAULT '',
  age INTEGER,
  sex TEXT,
  city TEXT NOT NULL DEFAULT '',
  data_policy_accepted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users read own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
CREATE POLICY "Users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
CREATE POLICY "Users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m JSONB := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
BEGIN
  INSERT INTO public.profiles (id, full_name, profession, document_number, age, sex, city, data_policy_accepted_at)
  VALUES (
    NEW.id,
    LEFT(COALESCE(m->>'full_name', m->>'name', ''), 120),
    LEFT(COALESCE(m->>'profession', ''), 80),
    LEFT(COALESCE(m->>'document_number', ''), 15),
    CASE WHEN (m->>'age') ~ '^\d{1,3}$' THEN (m->>'age')::int ELSE NULL END,
    CASE WHEN m->>'sex' IN ('Femenino','Masculino','Otro') THEN m->>'sex' ELSE NULL END,
    LEFT(COALESCE(m->>'city', ''), 80),
    CASE WHEN m->>'data_policy_accepted' = 'true' THEN now() ELSE NULL END
  ) ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END; $$;

CREATE TRIGGER on_auth_user_created_profile AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();