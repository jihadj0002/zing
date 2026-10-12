-- Bangladesh-first Dating App — PostgreSQL/PostGIS reference schema v1
-- Intended as a schema blueprint. For Django production use, translate to Django models
-- and migrations; do not apply blindly to a live database.
-- PostgreSQL 15+ recommended. Use a custom Django user model before first migration.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164 VARCHAR(20) UNIQUE,
  status VARCHAR(32) NOT NULL DEFAULT 'registered'
    CHECK (status IN ('registered','verification_pending','profile_setup','active',
      'temporarily_restricted','suspended','banned','deletion_pending','deleted')),
  phone_verified_at TIMESTAMPTZ,
  google_subject VARCHAR(255) UNIQUE,
  terms_version VARCHAR(40),
  privacy_version VARCHAR(40),
  age_gate_confirmed_at TIMESTAMPTZ,
  last_active_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  CHECK (phone_e164 IS NULL OR phone_e164 ~ '^\\+[1-9][0-9]{7,14}$')
);

CREATE TABLE auth_identities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  provider VARCHAR(20) NOT NULL CHECK (provider IN ('phone','google')),
  provider_subject VARCHAR(255) NOT NULL,
  provider_email VARCHAR(320),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ,
  UNIQUE(provider, provider_subject)
);
CREATE INDEX auth_identities_user_idx ON auth_identities(user_id);

CREATE TABLE otp_challenges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164 VARCHAR(20) NOT NULL,
  purpose VARCHAR(24) NOT NULL CHECK (purpose IN ('signup','login','account_recovery','phone_change')),
  otp_hash VARCHAR(255) NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  attempt_count SMALLINT NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  max_attempts SMALLINT NOT NULL DEFAULT 5 CHECK (max_attempts BETWEEN 1 AND 10),
  consumed_at TIMESTAMPTZ,
  request_ip_hash VARCHAR(128),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (expires_at > created_at)
);
CREATE INDEX otp_challenge_lookup_idx ON otp_challenges(phone_e164, purpose, created_at DESC);

CREATE TABLE devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  platform VARCHAR(10) NOT NULL CHECK (platform IN ('android','ios')),
  push_token TEXT,
  app_version VARCHAR(40),
  last_seen_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX devices_user_active_idx ON devices(user_id) WHERE revoked_at IS NULL;

CREATE TABLE user_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
  refresh_token_hash VARCHAR(255) NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  last_used_at TIMESTAMPTZ,
  rotated_from_id UUID REFERENCES user_sessions(id) ON DELETE SET NULL,
  CHECK (expires_at > created_at)
);
CREATE INDEX sessions_user_active_idx ON user_sessions(user_id, expires_at) WHERE revoked_at IS NULL;

CREATE TABLE profiles (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE RESTRICT,
  display_name VARCHAR(50) NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 50),
  date_of_birth DATE NOT NULL,
  gender_identity VARCHAR(50) NOT NULL,
  bio VARCHAR(500) NOT NULL DEFAULT '',
  occupation VARCHAR(100) NOT NULL DEFAULT '',
  education_level VARCHAR(40),
  height_cm SMALLINT CHECK (height_cm IS NULL OR height_cm BETWEEN 80 AND 250),
  relationship_intention VARCHAR(40),
  languages TEXT[] NOT NULL DEFAULT '{}',
  visibility VARCHAR(16) NOT NULL DEFAULT 'visible'
    CHECK (visibility IN ('visible','paused','hidden')),
  status VARCHAR(20) NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','pending_review','approved','rejected')),
  profile_completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX profiles_discovery_state_idx ON profiles(status, visibility);

CREATE TABLE interests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug VARCHAR(80) NOT NULL UNIQUE,
  display_name VARCHAR(80) NOT NULL,
  category VARCHAR(60) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE profile_interests (
  user_id UUID NOT NULL REFERENCES profiles(user_id) ON DELETE RESTRICT,
  interest_id UUID NOT NULL REFERENCES interests(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id, interest_id)
);

CREATE TABLE discovery_preferences (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE RESTRICT,
  min_age SMALLINT NOT NULL DEFAULT 18 CHECK (min_age BETWEEN 18 AND 100),
  max_age SMALLINT NOT NULL DEFAULT 99 CHECK (max_age BETWEEN 18 AND 100),
  max_distance_km INTEGER NOT NULL DEFAULT 25 CHECK (max_distance_km BETWEEN 1 AND 500),
  location_mode VARCHAR(12) NOT NULL DEFAULT 'nearby'
    CHECK (location_mode IN ('nearby','manual_area')),
  distance_filter_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  show_gender_ids TEXT[] NOT NULL DEFAULT '{}',
  reciprocal_preferences_required BOOLEAN NOT NULL DEFAULT TRUE,
  manual_area_id VARCHAR(80),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (min_age <= max_age),
  CHECK ((location_mode = 'nearby' AND distance_filter_enabled = TRUE)
      OR location_mode = 'manual_area')
);

CREATE TABLE user_locations (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE RESTRICT,
  location GEOGRAPHY(POINT,4326) NOT NULL,
  source VARCHAR(12) NOT NULL CHECK (source IN ('gps','manual_area')),
  area_id VARCHAR(80),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((source = 'gps' AND area_id IS NULL) OR source = 'manual_area')
);
CREATE INDEX user_locations_geo_idx ON user_locations USING GIST(location);

CREATE TABLE profile_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  storage_key VARCHAR(500) NOT NULL UNIQUE,
  thumbnail_key VARCHAR(500),
  position SMALLINT NOT NULL CHECK (position >= 0),
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  moderation_status VARCHAR(16) NOT NULL DEFAULT 'pending'
    CHECK (moderation_status IN ('pending','approved','rejected')),
  width INTEGER NOT NULL CHECK (width > 0),
  height INTEGER NOT NULL CHECK (height > 0),
  mime_type VARCHAR(100) NOT NULL CHECK (mime_type IN ('image/jpeg','image/png','image/webp','image/heic')),
  size_bytes BIGINT NOT NULL CHECK (size_bytes BETWEEN 1 AND 10485760),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX uniq_active_photo_position ON profile_photos(user_id, position) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uniq_active_primary_photo ON profile_photos(user_id) WHERE is_primary = TRUE AND deleted_at IS NULL;
CREATE INDEX profile_photos_approved_idx ON profile_photos(user_id, position) WHERE moderation_status='approved' AND deleted_at IS NULL;

CREATE TABLE swipes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  target_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  client_action_id UUID NOT NULL,
  action VARCHAR(12) NOT NULL CHECK (action IN ('like','pass')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (actor_user_id <> target_user_id),
  UNIQUE(actor_user_id, target_user_id),
  UNIQUE(actor_user_id, client_action_id)
);
CREATE INDEX swipes_target_action_idx ON swipes(target_user_id, action);
CREATE INDEX swipes_actor_action_idx ON swipes(actor_user_id, action);

CREATE TABLE matches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_low UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  user_high UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  status VARCHAR(16) NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','ended','under_review')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at TIMESTAMPTZ,
  ended_by UUID REFERENCES users(id) ON DELETE RESTRICT,
  end_reason VARCHAR(40) NOT NULL DEFAULT '',
  CHECK (user_low < user_high),
  UNIQUE(user_low, user_high),
  CHECK ((status = 'active' AND ended_at IS NULL) OR status <> 'active')
);
CREATE INDEX matches_user_low_status_idx ON matches(user_low, status, created_at DESC);
CREATE INDEX matches_user_high_status_idx ON matches(user_high, status, created_at DESC);

CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id UUID NOT NULL UNIQUE REFERENCES matches(id) ON DELETE RESTRICT,
  last_message_id UUID,
  last_message_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE RESTRICT,
  sender_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  client_message_id UUID NOT NULL,
  message_type VARCHAR(12) NOT NULL CHECK (message_type IN ('text','image','system')),
  body TEXT NOT NULL DEFAULT '',
  status VARCHAR(16) NOT NULL DEFAULT 'sent'
    CHECK (status IN ('sent','deleted','moderated')),
  sequence_number BIGINT NOT NULL CHECK (sequence_number > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  edited_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  CHECK (char_length(body) <= 4000),
  CHECK (message_type <> 'text' OR char_length(trim(body)) > 0),
  UNIQUE(sender_user_id, client_message_id),
  UNIQUE(conversation_id, sequence_number)
);
CREATE INDEX messages_conversation_sequence_idx ON messages(conversation_id, sequence_number DESC);

ALTER TABLE conversations
  ADD CONSTRAINT conversations_last_message_fk
  FOREIGN KEY (last_message_id) REFERENCES messages(id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE message_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID REFERENCES messages(id) ON DELETE RESTRICT,
  conversation_id UUID REFERENCES conversations(id) ON DELETE RESTRICT,
  uploaded_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  storage_key VARCHAR(500) NOT NULL UNIQUE,
  mime_type VARCHAR(100) NOT NULL CHECK (mime_type IN ('image/jpeg','image/png','image/webp','image/heic')),
  size_bytes BIGINT NOT NULL CHECK (size_bytes BETWEEN 1 AND 10485760),
  width INTEGER CHECK (width IS NULL OR width > 0),
  height INTEGER CHECK (height IS NULL OR height > 0),
  moderation_status VARCHAR(16) NOT NULL DEFAULT 'pending'
    CHECK (moderation_status IN ('pending','approved','rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((message_id IS NOT NULL) OR (conversation_id IS NOT NULL))
);
CREATE INDEX attachments_message_idx ON message_attachments(message_id);

CREATE TABLE conversation_user_state (
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE RESTRICT,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  last_read_sequence BIGINT NOT NULL DEFAULT 0 CHECK (last_read_sequence >= 0),
  muted_until TIMESTAMPTZ,
  archived_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(conversation_id, user_id)
);

CREATE TABLE user_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  blocked_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  reason_category VARCHAR(40),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (blocker_user_id <> blocked_user_id),
  UNIQUE(blocker_user_id, blocked_user_id)
);
CREATE INDEX blocks_blocked_idx ON user_blocks(blocked_user_id);

CREATE TABLE reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  reported_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  match_id UUID REFERENCES matches(id) ON DELETE RESTRICT,
  message_id UUID REFERENCES messages(id) ON DELETE RESTRICT,
  category VARCHAR(32) NOT NULL CHECK (category IN
    ('harassment','spam','impersonation','scam','threats','inappropriate_content','underage_concern','other')),
  description VARCHAR(2000) NOT NULL DEFAULT '',
  status VARCHAR(16) NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','triaged','in_review','actioned','dismissed','appealed','closed')),
  priority VARCHAR(12) NOT NULL DEFAULT 'normal'
    CHECK (priority IN ('low','normal','high','urgent')),
  assigned_moderator_id UUID REFERENCES users(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  CHECK (reporter_user_id <> reported_user_id)
);
CREATE INDEX reports_queue_idx ON reports(status, priority, created_at);
CREATE INDEX reports_target_idx ON reports(reported_user_id, created_at DESC);

CREATE TABLE moderation_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  target_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  moderator_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  report_id UUID REFERENCES reports(id) ON DELETE RESTRICT,
  action_type VARCHAR(32) NOT NULL CHECK (action_type IN
    ('warning','content_removal','discovery_restriction','messaging_restriction','temporary_suspension','permanent_ban','reversal')),
  reason_code VARCHAR(80) NOT NULL,
  internal_notes VARCHAR(4000) NOT NULL DEFAULT '',
  starts_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ,
  appeal_status VARCHAR(16) NOT NULL DEFAULT 'not_applicable'
    CHECK (appeal_status IN ('not_applicable','available','submitted','upheld','reversed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (expires_at IS NULL OR expires_at > starts_at)
);
CREATE INDEX moderation_target_idx ON moderation_actions(target_user_id, created_at DESC);

CREATE TABLE notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE RESTRICT,
  match_push BOOLEAN NOT NULL DEFAULT TRUE,
  message_push BOOLEAN NOT NULL DEFAULT TRUE,
  safety_push BOOLEAN NOT NULL DEFAULT TRUE,
  marketing_push BOOLEAN NOT NULL DEFAULT FALSE,
  message_preview BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  category VARCHAR(20) NOT NULL CHECK (category IN ('match','message','safety','system')),
  event_key VARCHAR(200) NOT NULL UNIQUE,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  status VARCHAR(16) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','sent','failed','suppressed')),
  attempt_count SMALLINT NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  next_attempt_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX notifications_user_created_idx ON notifications(user_id, created_at DESC);

CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id UUID REFERENCES users(id) ON DELETE RESTRICT,
  action VARCHAR(100) NOT NULL,
  target_type VARCHAR(80),
  target_id VARCHAR(100),
  request_id UUID,
  safe_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX audit_logs_target_idx ON audit_logs(target_type, target_id, created_at DESC);
CREATE INDEX audit_logs_actor_idx ON audit_logs(actor_user_id, created_at DESC);

CREATE TABLE data_deletion_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  status VARCHAR(16) NOT NULL DEFAULT 'requested'
    CHECK (status IN ('requested','processing','completed','failed','held_for_review')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  failure_code VARCHAR(80),
  retention_policy_version VARCHAR(40) NOT NULL
);
CREATE UNIQUE INDEX one_open_deletion_job_per_user
  ON data_deletion_jobs(user_id)
  WHERE status IN ('requested','processing','held_for_review');

CREATE TABLE discovery_impressions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  viewer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  candidate_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  ranking_version VARCHAR(40) NOT NULL,
  score_bucket SMALLINT CHECK (score_bucket IS NULL OR score_bucket BETWEEN 0 AND 100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (viewer_user_id <> candidate_user_id)
);
CREATE INDEX impressions_viewer_created_idx ON discovery_impressions(viewer_user_id, created_at DESC);

CREATE TABLE outbox_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type VARCHAR(100) NOT NULL,
  aggregate_type VARCHAR(80) NOT NULL,
  aggregate_id UUID NOT NULL,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at TIMESTAMPTZ,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_error_code VARCHAR(100)
);
CREATE INDEX outbox_pending_idx ON outbox_events(created_at) WHERE published_at IS NULL;

-- Additional application/service-level invariants to enforce in Django transactions:
-- 1. Profile DOB must satisfy the 18+ rule at registration and on any DOB change.
-- 2. A discoverable profile must have at least one approved active photo.
-- 3. A match requires reciprocal current Likes and no block/restriction.
-- 4. A conversation must only be accessed by one of the match's two participants.
-- 5. Message sender must be a participant; active match and block rules apply.
-- 6. Match pair must be normalized (user_low < user_high) before insert.
-- 7. Message sequence_number allocation must be atomic per conversation.
-- 8. Attachment must belong to sender/conversation and be approved before sending.
-- 9. user_locations must never be serialized to public profile API.
-- 10. Deletion/retention behavior must be implemented as explicit audited jobs.
