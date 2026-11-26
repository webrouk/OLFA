-- ═════════════════════════════════════════════════════════════════════════
-- A. Consultation chats: kept for N days (default 30) after the consultation
--    ends. Any new message from either side restarts the N days. When they
--    run out the conversation and everything in it is DELETED for both
--    (messages, attachments → storage_garbage), not hidden.
-- ═════════════════════════════════════════════════════════════════════════

-- When a consultation ended (NULL while it is still running).
CREATE FUNCTION olfa_consult_ended_at(p_status consultation_status, p_completed timestamptz, p_cancelled timestamptz, p_updated timestamptz)
RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_status
    WHEN 'COMPLETED' THEN COALESCE(p_completed, p_updated)
    WHEN 'CANCELLED' THEN COALESCE(p_cancelled, p_updated)
    WHEN 'DECLINED'  THEN p_updated
    WHEN 'REFUNDED'  THEN p_updated
    WHEN 'EXPIRED'   THEN p_updated
    ELSE NULL END
$$;

-- Deletion date of a consultation chat: N days after the later of "ended" and
-- "last message". NULL while the consultation is running (no countdown).
CREATE FUNCTION olfa_consult_chat_expires_at(p_conversation uuid) RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT GREATEST(olfa_consult_ended_at(k.status, k.completed_at, k.cancelled_at, k.updated_at), c.last_message_at)
         + make_interval(days => olfa_setting_int('consultations.chatRetentionDays', 30))
  FROM conversations c JOIN consultations k ON k.id = c.consultation_id
  WHERE c.id = p_conversation AND olfa_consult_ended_at(k.status, k.completed_at, k.cancelled_at, k.updated_at) IS NOT NULL
$$;

-- Messages: match chats need an ACTIVE match (unchanged); consultation chats
-- can be written while the consultation runs and, after it ends, until the
-- deletion date (a message moves the date forward).
CREATE OR REPLACE FUNCTION olfa_message_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE st match_status; k conversation_kind; exp timestamptz;
BEGIN
  SELECT c.kind, m.status INTO k, st FROM conversations c LEFT JOIN matches m ON m.id = c.match_id WHERE c.id = NEW.conversation_id;
  IF k = 'MATCH' AND st IS DISTINCT FROM 'ACTIVE' THEN
    RAISE EXCEPTION 'conversation is closed until the match is restored' USING ERRCODE = 'P0010';
  END IF;
  IF k = 'CONSULTATION' THEN
    exp := olfa_consult_chat_expires_at(NEW.conversation_id);
    IF exp IS NOT NULL AND NEW.created_at >= exp THEN
      RAISE EXCEPTION 'consultation chat has expired' USING ERRCODE = 'P0010';
    END IF;
  END IF;
  RETURN NEW;
END $$;

-- The list now also says which folder a row is in and whether a consultation
-- has ended (counselor inbox: Active · Ended · Archive).
DROP FUNCTION olfa_conversation_list(uuid, int, timestamptz);
CREATE FUNCTION olfa_conversation_list(p_user uuid, p_limit int, p_now timestamptz DEFAULT now())
RETURNS TABLE (conversation_id uuid, section text, list_position int, locked boolean, expires_at timestamptz, warn boolean, folder text, consult_ended boolean)
LANGUAGE sql STABLE AS $$
  WITH mine AS (
    SELECT c.id, c.kind, cm.folder, cm.retention_anchor_at, m.status AS match_status, m.ended_at,
           COALESCE(c.last_message_at, c.created_at) AS activity,
           CASE WHEN c.kind = 'CONSULTATION' THEN olfa_consult_ended_at(k.status, k.completed_at, k.cancelled_at, k.updated_at) END AS consult_end,
           c.last_message_at
    FROM conversation_members cm
    JOIN conversations c ON c.id = cm.conversation_id
    LEFT JOIN matches m ON m.id = c.match_id
    LEFT JOIN consultations k ON k.id = c.consultation_id
    WHERE cm.user_id = p_user AND (c.kind = 'CONSULTATION' OR m.status IN ('ACTIVE','UNMATCHED'))
  ), placed AS (
    SELECT id, CASE WHEN kind = 'CONSULTATION' THEN 'CONSULTATION' WHEN match_status = 'UNMATCHED' THEN 'UNMATCHED' ELSE folder::text END AS section,
      CASE WHEN kind = 'CONSULTATION' THEN
             CASE WHEN consult_end IS NULL THEN NULL
                  ELSE GREATEST(consult_end, last_message_at) + make_interval(days => olfa_setting_int('consultations.chatRetentionDays', 30)) END
           WHEN match_status = 'UNMATCHED' THEN ended_at + make_interval(days => olfa_setting_int('chat.unmatchedRetentionDays', 30))
           WHEN folder = 'ARCHIVE'       THEN retention_anchor_at + make_interval(days => olfa_setting_int('chat.archiveRetentionDays', 30))
           ELSE                               retention_anchor_at + make_interval(days => olfa_setting_int('chat.inboxRetentionDays', 15)) END AS expires_at,
      CASE WHEN kind = 'CONSULTATION' OR match_status = 'UNMATCHED' THEN NULL
           ELSE row_number() OVER (PARTITION BY (kind = 'CONSULTATION' OR match_status = 'UNMATCHED') ORDER BY activity DESC, id) END AS pos,
      folder, kind, consult_end, activity
    FROM mine
  )
  SELECT id, section, pos::int,
         (section IN ('INBOX','ARCHIVE') AND p_limit >= 0 AND pos > p_limit) AS locked,
         expires_at,
         CASE WHEN section = 'UNMATCHED' THEN false
              WHEN section = 'CONSULTATION' THEN expires_at IS NOT NULL AND p_now >= expires_at - make_interval(days => olfa_setting_int('consultations.chatWarnBeforeDays', 3))
              WHEN folder = 'ARCHIVE' THEN p_now >= expires_at - make_interval(days => olfa_setting_int('chat.archiveWarnBeforeDays', 7))
              ELSE p_now >= expires_at - make_interval(days => olfa_setting_int('chat.inboxRetentionDays', 15) - olfa_setting_int('chat.inboxWarnAfterDays', 10)) END,
         folder::text,
         (kind = 'CONSULTATION' AND consult_end IS NOT NULL)
  FROM placed
  WHERE NOT (section = 'CONSULTATION' AND expires_at IS NOT NULL AND p_now >= expires_at) -- past its date, waiting for the sweep: already gone for the user
  ORDER BY section, pos NULLS LAST, activity DESC
$$;

CREATE OR REPLACE FUNCTION olfa_run_retention(p_now timestamptz DEFAULT now())
RETURNS TABLE (action text, conversation_id uuid, user_id uuid) LANGUAGE plpgsql AS $$
DECLARE
  inbox_days int := olfa_setting_int('chat.inboxRetentionDays', 15);
  inbox_warn int := olfa_setting_int('chat.inboxWarnAfterDays', 10);
  arch_days  int := olfa_setting_int('chat.archiveRetentionDays', 30);
  arch_warn  int := olfa_setting_int('chat.archiveWarnBeforeDays', 7);
  unm_days   int := olfa_setting_int('chat.unmatchedRetentionDays', 30);
  k_warn     int := olfa_setting_int('consultations.chatWarnBeforeDays', 3);
BEGIN
  -- 1. warnings (once per retention cycle; a new message resets the cycle)
  RETURN QUERY
  WITH due AS (
    UPDATE conversation_members cm SET expiry_warned_at = p_now
    FROM conversations c JOIN matches m ON m.id = c.match_id
    WHERE c.id = cm.conversation_id AND m.status = 'ACTIVE' AND cm.expiry_warned_at IS NULL
      AND ((cm.folder = 'INBOX'   AND p_now >= cm.retention_anchor_at + make_interval(days => inbox_warn))
        OR (cm.folder = 'ARCHIVE' AND p_now >= cm.retention_anchor_at + make_interval(days => arch_days - arch_warn)))
    RETURNING cm.conversation_id, cm.user_id, cm.folder, cm.retention_anchor_at
  ), notified AS (
    INSERT INTO notifications (user_id, type, title_key, body_key, params, data)
    SELECT d.user_id, 'CONVERSATION_EXPIRING', 'push.chat_expiring.title', 'push.chat_expiring.body',
           jsonb_build_object('daysLeft', GREATEST(1, ceil(extract(epoch FROM (d.retention_anchor_at
             + make_interval(days => CASE WHEN d.folder = 'ARCHIVE' THEN arch_days ELSE inbox_days END) - p_now)) / 86400)::int)),
           jsonb_build_object('conversationId', d.conversation_id)
    FROM due d RETURNING 1
  )
  SELECT 'warned', d.conversation_id, d.user_id FROM due d;

  -- 1b. consultation chats: one warning per member, k_warn days before deletion
  RETURN QUERY
  WITH due AS (
    UPDATE conversation_members cm SET expiry_warned_at = p_now
    FROM conversations c
    WHERE c.id = cm.conversation_id AND c.kind = 'CONSULTATION' AND cm.expiry_warned_at IS NULL
      AND olfa_consult_chat_expires_at(c.id) IS NOT NULL
      AND p_now >= olfa_consult_chat_expires_at(c.id) - make_interval(days => k_warn)
      AND p_now <  olfa_consult_chat_expires_at(c.id)
    RETURNING cm.conversation_id, cm.user_id
  ), notified AS (
    INSERT INTO notifications (user_id, type, title_key, body_key, params, data)
    SELECT d.user_id, 'CONVERSATION_EXPIRING', 'push.consult_chat_expiring.title', 'push.consult_chat_expiring.body',
           jsonb_build_object('daysLeft', GREATEST(1, ceil(extract(epoch FROM (olfa_consult_chat_expires_at(d.conversation_id) - p_now)) / 86400)::int)),
           jsonb_build_object('conversationId', d.conversation_id)
    FROM due d RETURNING 1
  )
  SELECT 'warned', d.conversation_id, d.user_id FROM due d;

  -- 2. expiry of active conversations, per member
  RETURN QUERY
  DELETE FROM conversation_members cm USING conversations c, matches m
  WHERE c.id = cm.conversation_id AND m.id = c.match_id AND m.status = 'ACTIVE'
    AND p_now >= cm.retention_anchor_at + make_interval(days => CASE WHEN cm.folder = 'ARCHIVE' THEN arch_days ELSE inbox_days END)
  RETURNING 'expired', cm.conversation_id, cm.user_id;

  -- 3. unmatched for a month without a re-match → deleted for both
  RETURN QUERY
  DELETE FROM conversations c USING matches m
  WHERE m.id = c.match_id AND m.status = 'UNMATCHED' AND p_now >= m.ended_at + make_interval(days => unm_days)
  RETURNING 'deleted_unmatched', c.id, NULL::uuid;

  -- 3b. ended consultations past their date → conversation, messages and
  --     attachments deleted for both (the consultation record itself stays
  --     for payments, reviews and disputes).
  RETURN QUERY
  DELETE FROM conversations c
  WHERE c.kind = 'CONSULTATION' AND olfa_consult_chat_expires_at(c.id) IS NOT NULL AND p_now >= olfa_consult_chat_expires_at(c.id)
  RETURNING 'deleted_consultation', c.id, NULL::uuid;

  -- 4. conversations nobody can see any more
  RETURN QUERY
  DELETE FROM conversations c WHERE c.kind = 'MATCH' AND NOT EXISTS (SELECT 1 FROM conversation_members cm WHERE cm.conversation_id = c.id)
  RETURNING 'deleted_empty', c.id, NULL::uuid;
END $$;

-- "N days after completion" (write window) is replaced by the retention rule
-- above: the chat stays writable until its deletion date.
DELETE FROM system_settings WHERE key = 'consultations.chatOpenDaysAfterCompletion';
INSERT INTO system_settings (key, value, description) VALUES
  ('consultations.chatRetentionDays', '30', 'Consultation chats are deleted for both sides this many days after the consultation ends or after the last message, whichever is later'),
  ('consultations.chatWarnBeforeDays', '3', 'Notify both sides this many days before a consultation chat is deleted')
ON CONFLICT (key) DO NOTHING;

-- ═════════════════════════════════════════════════════════════════════════
-- B. Accounts managed on someone's behalf (a parent for a daughter or son,
--    or another person with the owner's consent). The profile is always the
--    OWNER's; the manager's name and relation are kept apart and only the
--    relation is shown publicly ("Managed by her father").
-- ═════════════════════════════════════════════════════════════════════════
CREATE TYPE managed_relation AS ENUM ('FATHER','MOTHER','BROTHER','SISTER','GRANDPARENT','UNCLE','AUNT','LEGAL_GUARDIAN','RELATIVE','FRIEND');
CREATE TYPE managed_phone_holder AS ENUM ('OWNER','MANAGER');

CREATE TABLE account_managers (
  user_id          uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  manager_name     varchar(60) NOT NULL CHECK (length(btrim(manager_name)) >= 2),
  relation         managed_relation NOT NULL,
  -- whose phone number signs in to this account
  phone_holder     managed_phone_holder NOT NULL DEFAULT 'MANAGER',
  -- the owner agreed to the account being managed (required, never assumed)
  owner_consent_at timestamptz NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  revoked_at       timestamptz,
  revoked_by       varchar(10) CHECK (revoked_by IN ('ACCOUNT','ADMIN')),
  CHECK ((revoked_at IS NULL) = (revoked_by IS NULL))
);
-- Members only: counselor accounts are never managed by someone else.
CREATE FUNCTION olfa_account_manager_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT account_type FROM users WHERE id = NEW.user_id) <> 'MEMBER' THEN
    RAISE EXCEPTION 'only member accounts can be managed on someone''s behalf' USING ERRCODE = 'P0072';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;
CREATE TRIGGER account_managers_guard BEFORE INSERT OR UPDATE ON account_managers FOR EACH ROW EXECUTE FUNCTION olfa_account_manager_guard();

-- ═════════════════════════════════════════════════════════════════════════
-- C. Compatibility questions inside a chat. Both people answer the questions
--    for their gender; answers are compared per TOPIC (a men's and a women's
--    version of the same question share a topic). The result exists only
--    once BOTH have answered everything — enforced here, not only in the API.
-- ═════════════════════════════════════════════════════════════════════════
CREATE TYPE compat_domain AS ENUM ('FINANCE','FUTURE','FAMILY_ROLES','LIFESTYLE','MARRIAGE');
CREATE TYPE compat_audience AS ENUM ('ALL','MALE','FEMALE');

CREATE TABLE compat_questions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic       varchar(40) NOT NULL CHECK (topic ~ '^[a-z][a-z0-9_]{1,39}$'),
  domain      compat_domain NOT NULL,
  audience    compat_audience NOT NULL DEFAULT 'ALL',
  prompt      jsonb NOT NULL CHECK (jsonb_typeof(prompt) = 'object' AND prompt ? 'ar' AND prompt ? 'en' AND prompt ? 'fr'),
  -- [{key, value (0..10), label:{ar,en,fr}}]
  options     jsonb NOT NULL CHECK (jsonb_typeof(options) = 'array' AND jsonb_array_length(options) BETWEEN 2 AND 6),
  weight      smallint NOT NULL DEFAULT 3 CHECK (weight BETWEEN 1 AND 10),
  -- SCALE: closer values = more compatible · MATCH: same value or not
  scoring     varchar(5) NOT NULL DEFAULT 'SCALE' CHECK (scoring IN ('SCALE','MATCH')),
  active      boolean NOT NULL DEFAULT true,
  sort_order  int NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (topic, audience)
);

-- A topic is either one question for everyone or a men's + women's pair, in
-- one domain; option keys are unique and values are whole numbers 0..10.
CREATE FUNCTION olfa_compat_question_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM compat_questions q WHERE q.topic = NEW.topic AND q.id <> NEW.id
             AND (q.audience = 'ALL' OR NEW.audience = 'ALL' OR q.domain <> NEW.domain)) THEN
    RAISE EXCEPTION 'a topic is one question for everyone or a men''s and women''s pair in the same domain' USING ERRCODE = 'P0073';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(NEW.options) o
             WHERE NOT (o ? 'key' AND o ? 'value' AND o ? 'label')
                OR jsonb_typeof(o->'value') <> 'number' OR (o->>'value')::numeric NOT BETWEEN 0 AND 10 OR (o->>'value')::numeric <> trunc((o->>'value')::numeric)
                OR NOT (o->'label' ? 'ar' AND o->'label' ? 'en' AND o->'label' ? 'fr'))
     OR (SELECT count(DISTINCT o->>'key') FROM jsonb_array_elements(NEW.options) o) <> jsonb_array_length(NEW.options) THEN
    RAISE EXCEPTION 'invalid answer options' USING ERRCODE = 'P0073';
  END IF;
  -- once answered, the options are frozen (results stay comparable): add a new question instead
  IF TG_OP = 'UPDATE' AND NEW.options IS DISTINCT FROM OLD.options AND EXISTS (SELECT 1 FROM compat_answers a WHERE a.question_id = NEW.id) THEN
    RAISE EXCEPTION 'answered questions keep their options; deactivate it and add a new one' USING ERRCODE = 'P0073';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- One questionnaire per conversation; the questions are fixed when it starts
-- (editing the bank later never changes a running questionnaire).
CREATE TABLE compat_sessions (
  conversation_id  uuid PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
  started_by       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  male_questions   uuid[] NOT NULL CHECK (cardinality(male_questions) > 0),
  female_questions uuid[] NOT NULL CHECK (cardinality(female_questions) > 0),
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE compat_answers (
  conversation_id uuid NOT NULL REFERENCES compat_sessions(conversation_id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  question_id     uuid NOT NULL REFERENCES compat_questions(id) ON DELETE RESTRICT,
  option_key      varchar(20) NOT NULL,
  answered_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id, question_id)
);
CREATE TRIGGER compat_questions_guard BEFORE INSERT OR UPDATE ON compat_questions FOR EACH ROW EXECUTE FUNCTION olfa_compat_question_guard();

CREATE TABLE compat_results (
  conversation_id uuid PRIMARY KEY REFERENCES compat_sessions(conversation_id) ON DELETE CASCADE,
  score           smallint NOT NULL CHECK (score BETWEEN 0 AND 100),
  breakdown       jsonb NOT NULL,
  message_id      uuid REFERENCES messages(id) ON DELETE SET NULL,
  computed_at     timestamptz NOT NULL DEFAULT now()
);

-- The questions a member answers in a questionnaire (by their gender).
CREATE FUNCTION olfa_compat_my_questions(p_conversation uuid, p_user uuid) RETURNS uuid[] LANGUAGE sql STABLE AS $$
  SELECT CASE p.gender WHEN 'MALE' THEN s.male_questions ELSE s.female_questions END
  FROM compat_sessions s JOIN user_profiles p ON p.user_id = p_user
  WHERE s.conversation_id = p_conversation
$$;

-- Answers: a member of the chat, a question from their own set, an option that
-- exists, and nothing changes once the result is out.
CREATE FUNCTION olfa_compat_answer_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM conversation_members WHERE conversation_id = NEW.conversation_id AND user_id = NEW.user_id) THEN
    RAISE EXCEPTION 'not a member of this conversation' USING ERRCODE = 'P0074';
  END IF;
  IF EXISTS (SELECT 1 FROM compat_results WHERE conversation_id = NEW.conversation_id) THEN
    RAISE EXCEPTION 'answers are final once the result is shown' USING ERRCODE = 'P0074';
  END IF;
  IF NOT (NEW.question_id = ANY (olfa_compat_my_questions(NEW.conversation_id, NEW.user_id))) THEN
    RAISE EXCEPTION 'this question is not in your set' USING ERRCODE = 'P0074';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM compat_questions q, jsonb_array_elements(q.options) o WHERE q.id = NEW.question_id AND o->>'key' = NEW.option_key) THEN
    RAISE EXCEPTION 'unknown answer' USING ERRCODE = 'P0074';
  END IF;
  NEW.answered_at := now();
  RETURN NEW;
END $$;
CREATE TRIGGER compat_answers_guard BEFORE INSERT OR UPDATE ON compat_answers FOR EACH ROW EXECUTE FUNCTION olfa_compat_answer_guard();

-- Progress per member, without revealing anybody's answers.
CREATE FUNCTION olfa_compat_progress(p_conversation uuid)
RETURNS TABLE (user_id uuid, answered int, total int) LANGUAGE sql STABLE AS $$
  SELECT cm.user_id,
         (SELECT count(*)::int FROM compat_answers a WHERE a.conversation_id = p_conversation AND a.user_id = cm.user_id
            AND a.question_id = ANY (olfa_compat_my_questions(p_conversation, cm.user_id))),
         cardinality(olfa_compat_my_questions(p_conversation, cm.user_id))
  FROM conversation_members cm WHERE cm.conversation_id = p_conversation
$$;

-- No result before BOTH have answered all their questions.
CREATE FUNCTION olfa_compat_result_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT count(*) FROM olfa_compat_progress(NEW.conversation_id) WHERE answered = total AND total > 0) < 2 THEN
    RAISE EXCEPTION 'both people must finish before the result exists' USING ERRCODE = 'P0075';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER compat_results_guard BEFORE INSERT ON compat_results FOR EACH ROW EXECUTE FUNCTION olfa_compat_result_guard();

INSERT INTO system_settings (key, value, description) VALUES
  ('compat.enabled', 'true', 'In-chat compatibility questions for matched members (kill switch)')
ON CONFLICT (key) DO NOTHING;

INSERT INTO compat_questions (topic, domain, audience, weight, scoring, prompt, options, sort_order) VALUES
  ('fin_budget', 'FINANCE', 'ALL', 4, 'SCALE', '{"ar": "كيف تفضّل إدارة مال الأسرة؟", "en": "How should the household money be managed?", "fr": "Comment gérer l’argent du foyer ?"}', '[{"key": "o0", "value": 0, "label": {"ar": "حساب مشترك بالكامل", "en": "Fully shared", "fr": "Entièrement en commun"}}, {"key": "o1", "value": 1, "label": {"ar": "مشترك في الغالب", "en": "Mostly shared", "fr": "Surtout en commun"}}, {"key": "o2", "value": 2, "label": {"ar": "مناصفة", "en": "Half and half", "fr": "Moitié-moitié"}}, {"key": "o3", "value": 3, "label": {"ar": "منفصل في الغالب", "en": "Mostly separate", "fr": "Surtout séparé"}}, {"key": "o4", "value": 4, "label": {"ar": "منفصل بالكامل", "en": "Fully separate", "fr": "Entièrement séparé"}}]', 0),
  ('fin_contribution', 'FINANCE', 'MALE', 5, 'SCALE', '{"ar": "هل تتوقع أن تشارك زوجتك في مصروفات البيت؟", "en": "Do you expect your wife to contribute to household expenses?", "fr": "Attendez-vous de votre épouse qu’elle participe aux dépenses du foyer ?"}', '[{"key": "o0", "value": 0, "label": {"ar": "لا، هذه مسؤوليتي", "en": "No, that is my responsibility", "fr": "Non, c’est ma responsabilité"}}, {"key": "o1", "value": 1, "label": {"ar": "إن رغبت هي", "en": "Only if she wishes", "fr": "Seulement si elle le souhaite"}}, {"key": "o2", "value": 2, "label": {"ar": "بجزء بسيط", "en": "A small share", "fr": "Une petite part"}}, {"key": "o3", "value": 3, "label": {"ar": "بالتساوي", "en": "Equally", "fr": "À parts égales"}}]', 10),
  ('fin_contribution', 'FINANCE', 'FEMALE', 5, 'SCALE', '{"ar": "هل تنوين المشاركة في مصروفات البيت؟", "en": "Do you plan to contribute to household expenses?", "fr": "Comptez-vous participer aux dépenses du foyer ?"}', '[{"key": "o0", "value": 0, "label": {"ar": "لا، أتوقع أن يتكفّل بها الزوج", "en": "No, I expect my husband to cover them", "fr": "Non, j’attends que mon mari les assume"}}, {"key": "o1", "value": 1, "label": {"ar": "إن رغبت أنا", "en": "Only if I choose to", "fr": "Seulement si je le décide"}}, {"key": "o2", "value": 2, "label": {"ar": "بجزء بسيط", "en": "A small share", "fr": "Une petite part"}}, {"key": "o3", "value": 3, "label": {"ar": "بالتساوي", "en": "Equally", "fr": "À parts égales"}}]', 20),
  ('fin_saving', 'FINANCE', 'ALL', 3, 'SCALE', '{"ar": "بين الادخار والإنفاق، أين تقف؟", "en": "Saving or spending — where do you stand?", "fr": "Épargner ou dépenser — où vous situez-vous ?"}', '[{"key": "o0", "value": 0, "label": {"ar": "أدّخر معظم الدخل", "en": "I save most of the income", "fr": "J’épargne l’essentiel"}}, {"key": "o1", "value": 1, "label": {"ar": "أدّخر جزءًا ثابتًا", "en": "I save a fixed share", "fr": "J’épargne une part fixe"}}, {"key": "o2", "value": 2, "label": {"ar": "أدّخر ما يتبقى", "en": "I save what is left", "fr": "J’épargne ce qui reste"}}, {"key": "o3", "value": 3, "label": {"ar": "أستمتع بالحاضر", "en": "I enjoy the present", "fr": "Je profite du présent"}}]', 30),
  ('fut_children', 'FUTURE', 'ALL', 5, 'SCALE', '{"ar": "متى تودّ إنجاب الأطفال؟", "en": "When would you like to have children?", "fr": "Quand aimeriez-vous avoir des enfants ?"}', '[{"key": "o0", "value": 0, "label": {"ar": "بعد الزواج مباشرة", "en": "Soon after marriage", "fr": "Peu après le mariage"}}, {"key": "o1", "value": 1, "label": {"ar": "خلال سنتين", "en": "Within two years", "fr": "Dans les deux ans"}}, {"key": "o2", "value": 2, "label": {"ar": "بعد ثلاث سنوات أو أكثر", "en": "After three years or more", "fr": "Après trois ans ou plus"}}, {"key": "o3", "value": 3, "label": {"ar": "غير متأكد بعد", "en": "Not sure yet", "fr": "Pas encore sûr(e)"}}]', 40),
  ('fut_home', 'FUTURE', 'ALL', 3, 'SCALE', '{"ar": "أين تحب أن تعيشا؟", "en": "Where would you like to live?", "fr": "Où aimeriez-vous vivre ?"}', '[{"key": "o0", "value": 0, "label": {"ar": "قرب عائلتي", "en": "Near my family", "fr": "Près de ma famille"}}, {"key": "o1", "value": 1, "label": {"ar": "مرن حسب الظروف", "en": "Flexible", "fr": "Flexible"}}, {"key": "o2", "value": 2, "label": {"ar": "في أي مكان، حتى خارج البلد", "en": "Anywhere, even abroad", "fr": "N’importe où, même à l’étranger"}}]', 50),
  ('fut_work', 'FUTURE', 'MALE', 5, 'SCALE', '{"ar": "هل تفضّل أن تعمل زوجتك بعد الزواج؟", "en": "Would you like your wife to work after marriage?", "fr": "Souhaitez-vous que votre épouse travaille après le mariage ?"}', '[{"key": "o0", "value": 0, "label": {"ar": "أفضّل ألّا تعمل", "en": "I prefer she doesn’t", "fr": "Je préfère qu’elle ne travaille pas"}}, {"key": "o1", "value": 1, "label": {"ar": "عمل جزئي أو من البيت", "en": "Part-time or from home", "fr": "Temps partiel ou à domicile"}}, {"key": "o2", "value": 2, "label": {"ar": "القرار لها", "en": "It is her decision", "fr": "C’est sa décision"}}, {"key": "o3", "value": 3, "label": {"ar": "نعم، بدوام كامل", "en": "Yes, full-time", "fr": "Oui, à temps plein"}}]', 60),
  ('fut_work', 'FUTURE', 'FEMALE', 5, 'SCALE', '{"ar": "هل تريدين الاستمرار في العمل بعد الزواج؟", "en": "Do you want to keep working after marriage?", "fr": "Voulez-vous continuer à travailler après le mariage ?"}', '[{"key": "o0", "value": 0, "label": {"ar": "لا", "en": "No", "fr": "Non"}}, {"key": "o1", "value": 1, "label": {"ar": "عمل جزئي أو من البيت", "en": "Part-time or from home", "fr": "Temps partiel ou à domicile"}}, {"key": "o2", "value": 2, "label": {"ar": "لم أقرّر بعد", "en": "I have not decided", "fr": "Je n’ai pas décidé"}}, {"key": "o3", "value": 3, "label": {"ar": "نعم، بدوام كامل", "en": "Yes, full-time", "fr": "Oui, à temps plein"}}]', 70),
  ('fam_chores', 'FAMILY_ROLES', 'ALL', 3, 'SCALE', '{"ar": "كيف تتوزع أعمال البيت؟", "en": "How should housework be shared?", "fr": "Comment partager les tâches ménagères ?"}', '[{"key": "o0", "value": 0, "label": {"ar": "على الزوجة في الغالب", "en": "Mostly the wife", "fr": "Surtout l’épouse"}}, {"key": "o1", "value": 1, "label": {"ar": "الزوجة مع مساعدة الزوج", "en": "The wife, with the husband’s help", "fr": "L’épouse, avec l’aide du mari"}}, {"key": "o2", "value": 2, "label": {"ar": "بالتساوي بيننا", "en": "Shared equally", "fr": "À parts égales"}}]', 80),
  ('fam_inlaws', 'FAMILY_ROLES', 'ALL', 4, 'SCALE', '{"ar": "السكن بالنسبة لأهل الزوج", "en": "Living arrangement with the husband’s family", "fr": "Logement par rapport à la belle-famille"}', '[{"key": "o0", "value": 0, "label": {"ar": "معهم في نفس البيت", "en": "In the same house", "fr": "Dans la même maison"}}, {"key": "o1", "value": 1, "label": {"ar": "قريب منهم", "en": "Close to them", "fr": "Près d’eux"}}, {"key": "o2", "value": 2, "label": {"ar": "بيت مستقل", "en": "An independent home", "fr": "Un logement indépendant"}}]', 90),
  ('fam_decisions', 'FAMILY_ROLES', 'ALL', 4, 'SCALE', '{"ar": "القرارات الكبيرة في الأسرة", "en": "Big family decisions", "fr": "Les grandes décisions familiales"}', '[{"key": "o0", "value": 0, "label": {"ar": "يقرّرها الزوج بعد المشورة", "en": "The husband decides after consulting", "fr": "Le mari décide après concertation"}}, {"key": "o1", "value": 1, "label": {"ar": "نقرّرها معًا بالتساوي", "en": "We decide together, equally", "fr": "Nous décidons ensemble, à égalité"}}]', 100),
  ('life_weekend', 'LIFESTYLE', 'ALL', 2, 'SCALE', '{"ar": "كيف تحب قضاء العطلة؟", "en": "How do you like to spend weekends?", "fr": "Comment aimez-vous passer le week-end ?"}', '[{"key": "o0", "value": 0, "label": {"ar": "في البيت", "en": "At home", "fr": "À la maison"}}, {"key": "o1", "value": 1, "label": {"ar": "بين البيت والخروج", "en": "A mix", "fr": "Un peu des deux"}}, {"key": "o2", "value": 2, "label": {"ar": "خارج البيت مع العائلة أو الأصدقاء", "en": "Out with family or friends", "fr": "Dehors en famille ou entre amis"}}]', 110),
  ('life_travel', 'LIFESTYLE', 'ALL', 2, 'SCALE', '{"ar": "السفر", "en": "Travel", "fr": "Les voyages"}', '[{"key": "o0", "value": 0, "label": {"ar": "نادرًا", "en": "Rarely", "fr": "Rarement"}}, {"key": "o1", "value": 1, "label": {"ar": "مرة في السنة", "en": "Once a year", "fr": "Une fois par an"}}, {"key": "o2", "value": 2, "label": {"ar": "عدة مرات في السنة", "en": "Several times a year", "fr": "Plusieurs fois par an"}}]', 120),
  ('life_religion', 'LIFESTYLE', 'ALL', 5, 'SCALE', '{"ar": "مكانة الالتزام الديني في الحياة اليومية", "en": "Religious practice in daily life", "fr": "La pratique religieuse au quotidien"}', '[{"key": "o0", "value": 0, "label": {"ar": "أساسية جدًا", "en": "Essential", "fr": "Essentielle"}}, {"key": "o1", "value": 1, "label": {"ar": "مهمّة", "en": "Important", "fr": "Importante"}}, {"key": "o2", "value": 2, "label": {"ar": "أمر شخصي", "en": "A personal matter", "fr": "Une affaire personnelle"}}]', 130),
  ('mar_wedding', 'MARRIAGE', 'ALL', 2, 'SCALE', '{"ar": "حجم حفل الزفاف", "en": "Size of the wedding", "fr": "Taille du mariage"}', '[{"key": "o0", "value": 0, "label": {"ar": "عائلي صغير", "en": "Small, family only", "fr": "Petit, en famille"}}, {"key": "o1", "value": 1, "label": {"ar": "متوسط", "en": "Medium", "fr": "Moyen"}}, {"key": "o2", "value": 2, "label": {"ar": "كبير", "en": "Large", "fr": "Grand"}}]', 140),
  ('mar_timeline', 'MARRIAGE', 'ALL', 4, 'SCALE', '{"ar": "متى تودّ الزواج إذا حصل التوافق؟", "en": "If it works out, when would you like to marry?", "fr": "Si cela fonctionne, quand aimeriez-vous vous marier ?"}', '[{"key": "o0", "value": 0, "label": {"ar": "خلال ستة أشهر", "en": "Within six months", "fr": "Dans les six mois"}}, {"key": "o1", "value": 1, "label": {"ar": "خلال سنة", "en": "Within a year", "fr": "Dans l’année"}}, {"key": "o2", "value": 2, "label": {"ar": "خلال سنة إلى سنتين", "en": "In one to two years", "fr": "Dans un à deux ans"}}]', 150),
  ('mar_conflict', 'MARRIAGE', 'ALL', 4, 'SCALE', '{"ar": "عند الخلاف، كيف تفضّل حلّه؟", "en": "When you disagree, how do you prefer to resolve it?", "fr": "En cas de désaccord, comment préférez-vous le régler ?"}', '[{"key": "o0", "value": 0, "label": {"ar": "نتحدث فورًا", "en": "Talk it through right away", "fr": "En parler tout de suite"}}, {"key": "o1", "value": 1, "label": {"ar": "نهدأ أولًا ثم نتحدث", "en": "Calm down first, then talk", "fr": "Se calmer d’abord, puis en parler"}}, {"key": "o2", "value": 2, "label": {"ar": "نستعين بالعائلة", "en": "Ask the family to help", "fr": "Faire appel à la famille"}}]', 160)
ON CONFLICT (topic, audience) DO NOTHING;
