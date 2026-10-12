SOFTWARE REQUIREMENTS
SPECIFICATION
Bangladesh-First Dating & Matchmaking App
Flutter · Django REST Framework · PostgreSQL/PostGIS · Django Channels

Document field	Value
Version	1.0 — Final baseline
Date	11 October 2026
Platforms	Android and iOS
Launch market	Bangladesh; controlled beta in selected areas
Authentication	Phone OTP + Google Sign-In
Messaging	Text and image attachments
Monetization	Free MVP; no paid boosts or subscriptions at launch
Location	Nearby discovery with approximate distance; manual area fallback
Status	Engineering baseline; policy/legal review required before public launch

Purpose: define product behavior, architecture, database entities and constraints, API contracts, delivery backlog, and testable acceptance criteria. This specification is intended for product, design, Flutter, backend, QA, and operations teams.

1. Executive summary
Build an adults-only dating app for Bangladesh. Users register using phone OTP or Google Sign-In, complete a profile, choose discovery preferences, discover eligible nearby people, like/pass profiles, create mutual matches, and chat through text and image attachments. Safety and privacy are first-class MVP features.
The MVP is intentionally free. Do not implement billing, boosts, paid likes, or subscription entitlements in Release 1. Keep the architecture extensible, but avoid payment complexity until product-market fit is validated.
Recommended architecture: Flutter client; Django REST Framework API; Django Channels for authenticated WebSockets; PostgreSQL with PostGIS; Redis for cache/rate limits/channel layer; Celery for asynchronous work; private S3-compatible storage for media; FCM/APNs for push notifications.
2. Fixed product decisions
Decision	Requirement
Market	Bangladesh-first; beta may begin in Dhaka or another selected service area. Market launch is not a restriction on future expansion.
Age	18+ only. Store date of birth privately; compute age from date of birth on the server.
Authentication	Phone OTP and Google Sign-In. Provider identity must be verified server-side. Apple Sign-In is a later option.
Messaging	Text + images in MVP; no voice/video calls.
Monetization	Free MVP. No paid tiers or feature gates. No billing endpoints required for launch.
Discovery	Nearby with approximate distance and a manual city/area fallback if location permission is denied.
Mobile	Flutter/Dart; Android and iOS.
Backend	Django + Django REST Framework + Django Channels.
Persistence	PostgreSQL + PostGIS.
Async	Celery + Redis; reliable outbox/event publication for critical events.
Media	Private object storage; signed URLs; validated uploads; EXIF stripping and moderation.
Safety	Block, report, unmatch, age gate, account restrictions, deletion workflow, moderation admin.

3. Goals, non-goals, and success measures
3.1 Goals
    • Create a reliable end-to-end journey from registration to first mutual match and message.
    • Return only eligible, approved, non-blocked profiles in discovery.
    • Make matching and message sending idempotent and safe under concurrent requests.
    • Provide clear safety controls and a workable moderation process before public launch.
    • Maintain a privacy-minimizing approach to location, media, account data, and notifications.
3.2 Non-goals for MVP
    • Paid subscriptions, boosts, super-likes, and in-app purchases.
    • Voice/video calls, live location sharing, public anonymous chat, or payments between users.
    • Machine-learning ranking; start with explainable eligibility rules and configurable scoring.
    • Microservices for every domain; use a modular monolith with independently scalable workers.
3.3 Product metrics
Track profile completion, eligible candidate availability, first-like time, like-to-match conversion, match-to-first-message conversion, D1/D7 retention, crash-free sessions, report response time, repeat-offender rate, and latency. Use privacy-conscious analytics and do not log raw message bodies or precise coordinates by default.
4. User roles and account lifecycle
Role/state	Permissions / behavior
Guest	Can see marketing/welcome screens and begin registration.
Registered / verification pending	Can complete verification; no discovery or messaging.
Profile setup	Can complete onboarding and upload photos; not discoverable.
Active	Can discover, like/pass, match, chat, and use safety controls.
Temporarily restricted	Specific features blocked according to moderation action.
Suspended	Sign-in or core use restricted; show safe explanation and appeal path where applicable.
Banned	Cannot use the service; revoke sessions and block new interaction.
Deletion pending	Removed from discovery immediately; deletion job runs.
Deleted	Account no longer usable; retention exceptions follow approved policy.
Moderator/admin	Least-privilege staff access; sensitive actions audited.

A premium-user role does not exist in the MVP. Account state and staff role are separate. The backend is authoritative for every state transition.
5. Functional requirements
5.1 Authentication and sessions
ID	Requirement
AUTH-001	Register with phone number and OTP; normalize phone numbers to E.164 where possible.
AUTH-002	Request OTP with per-phone, per-IP, device, and global rate limits; return generic responses to avoid account enumeration.
AUTH-003	OTP expires after a short configurable period (recommended 5 minutes), has a bounded attempt count, and is single-use.
AUTH-004	Verify Google ID tokens on the backend using Google's supported verification process; never trust a client-supplied user ID or email alone.
AUTH-005	Link identities only after proof of control of both identities; prevent silent account merging.
AUTH-006	Issue short-lived access credentials and rotated/revocable refresh credentials. Store mobile tokens in OS-backed secure storage.
AUTH-007	Support logout current session and revoke all sessions; revoke sessions on ban, account deletion, or security event.
AUTH-008	Require Terms/Privacy version acceptance and explicit 18+ confirmation.
AUTH-009	Apply server-side account-state checks on all protected APIs and WebSocket connections.

5.2 Onboarding and profile
ID	Requirement
PROF-001	Onboarding is resumable; persist each accepted step on the server.
PROF-002	Collect display name (1–50 chars), date of birth, gender identity, show-me preferences, and at least one approved photo.
PROF-003	Optional fields: bio (max 500 chars), interests (max 10), occupation (max 100 chars), languages, height, education, and relationship intention.
PROF-004	Never expose date of birth, phone, email, exact coordinates, internal moderation status, or auth fields in public profile responses.
PROF-005	Users can pause/hide discovery and update their preferences.
PROF-006	Profile becomes discoverable only after age, status, required fields, and photo approval checks pass.
PROF-007	Allow photo ordering/removal; only approved photos may be served in discovery.

5.3 Media
ID	Requirement
MEDIA-001	Use a private object store and short-lived upload URLs; do not accept arbitrary public image URLs.
MEDIA-002	Allow supported image types (JPEG/PNG and HEIC only if the pipeline supports it), maximum 10 MB per source image by default.
MEDIA-003	Validate magic bytes, MIME type, dimensions, and size; decode and re-encode; strip EXIF/GPS metadata.
MEDIA-004	Run safety screening before public display; support human review for flagged content.
MEDIA-005	Expire abandoned pending uploads and remove media on deletion according to retention policy.

5.4 Discovery
ID	Requirement
DISC-001	Return a cursor-paginated feed of eligible profiles; never return the current user.
DISC-002	Filter hidden, unapproved, banned, suspended, blocked, previously acted-on, and otherwise ineligible accounts.
DISC-003	Apply viewer preferences and reciprocal preference compatibility where configured.
DISC-004	Use PostGIS for server-side distance filtering. Never return exact candidate coordinates.
DISC-005	If location permission is denied, allow user-selected city/area discovery with clear limitations.
DISC-006	Use a versioned, configurable rank score after hard eligibility filters. Initial score: 35% interest compatibility, 25% reciprocal preference fit, 20% proximity, 10% age/preference fit, 10% profile completeness. Normalize components 0–1 and tune with evidence.
DISC-007	Use randomized tie-breaking and exposure diversity; do not rank on protected traits as hidden penalties.
DISC-008	Do not fetch and sort the entire user population in application memory; use indexed database filtering and bounded candidate sets.

5.5 Swipes and matches
ID	Requirement
MATCH-001	Support Like and Pass. The API accepts a client action UUID for idempotency.
MATCH-002	Persist one current directional swipe state per actor/target pair; if undo/history is added later, introduce a separate event-history table.
MATCH-003	Create a match only when reciprocal likes exist and both users remain eligible with no blocking relationship.
MATCH-004	Concurrent reciprocal likes create exactly one match and one conversation.
MATCH-005	Create the match and conversation in a database transaction; publish events after commit through an outbox or reliable job.
MATCH-006	Only the two participants can read match details or conversation data.
MATCH-007	Unmatch ends the match and disables sending; do not automatically rematch based on old likes.
MATCH-008	Block is distinct from unmatch and immediately prevents discovery and interaction.

5.6 Messaging
ID	Requirement
CHAT-001	Support text messages and image attachments only in MVP; no voice/video.
CHAT-002	Only participants in an active match may read/send messages; recheck block and moderation state on every operation.
CHAT-003	Persist message before returning successful-send acknowledgement.
CHAT-004	Use client_message_id unique per sender to deduplicate retries.
CHAT-005	Use conversation-scoped sequence numbers for stable ordering and cursor pagination.
CHAT-006	Support pending/sent/failed client state, retry with exponential backoff and jitter, and reconcile after reconnect.
CHAT-007	Image messages use the same private upload/validation/moderation pipeline as profile images.
CHAT-008	Push payloads should contain minimal content by default; message previews are an explicit user preference.
CHAT-009	Use authenticated WebSockets for live events, but never bypass domain authorization through WebSocket handlers.
CHAT-010	Unmatch/block/restriction closes or limits active sockets and prevents subsequent sends.

5.7 Notifications
ID	Requirement
NOTIF-001	Use FCM/APNs for match and message alerts.
NOTIF-002	Store device tokens per device, invalidate rejected tokens, and support notification category preferences.
NOTIF-003	Use Celery or equivalent async delivery; retry transient errors with bounded retries.
NOTIF-004	Deep links revalidate authorization on the destination screen.

5.8 Safety, privacy, and account
ID	Requirement
SAFE-001	Users can block/unblock accounts and report profiles or messages.
SAFE-002	Reports include category, optional description, target, reporter, relevant match/message references, priority, and status.
SAFE-003	Report records and moderator notes are private; do not reveal reporter identity to the reported user.
SAFE-004	Provide moderation queue, assigned reviewer, action history, escalation, and appeal path.
SAFE-005	Account deletion immediately removes the user from discovery and revokes sessions; background processing handles dependent data.
SAFE-006	Data export and deletion workflows follow a published policy and applicable law; legal/security records may have controlled retention.
SAFE-007	Provide age gate and a process for handling underage reports. Age confirmation alone is not proof of age.
SAFE-008	Do not infer sensitive traits from photos or message content.

5.9 Admin
ID	Requirement
ADMIN-001	Role-based staff access; least privilege.
ADMIN-002	Search users by internal ID and permitted identifiers; inspect account state and verification.
ADMIN-003	Review reports, view permitted evidence, assign cases, apply restrictions, and record reason codes.
ADMIN-004	Audit privileged access and all moderation/account actions; logs must not contain OTPs, tokens, or unnecessary message content.
ADMIN-005	Expose aggregate product/system health and queue failures without unrestricted access to private data.

6. Product rules and ranking
6.1 Candidate eligibility order
    1. Current user is authenticated, active, verified as required, and has completed onboarding.
    2. Candidate is a different active user, old enough, approved, visible, and has required approved media.
    3. Both users' gender/show-me and age preferences are compatible; apply reciprocal preference rule if enabled.
    4. Distance filter passes when location mode is enabled; manual-area mode uses area/city matching instead.
    5. Neither user has blocked the other; candidate has not already been acted on under current queue policy.
    6. Apply configurable ranking, diversity, and exposure controls only after hard eligibility filters.
6.2 Distance privacy
Store a geography point in a private user_locations table. Display only approximate bands or rounded distance. Never expose latitude/longitude in profile APIs. Limit update frequency, restrict staff access, and document location retention. When GPS is denied, the user can select a city/area; do not pretend the area is GPS-accurate.
7. Architecture and code layout
Component	Responsibility
Flutter	UI, local state, secure token storage, upload UI, push handling, REST/WebSocket client.
Django REST Framework	Authentication adapters, serializers, permissions, domain services, REST API.
Django Channels	Authenticated real-time connections and event delivery.
PostgreSQL/PostGIS	Source of truth, relational constraints, geo filtering, transactions.
Redis	Cache, rate-limit counters, Channels layer; not the durable source of truth.
Celery	OTP/email delivery, media processing, notifications, deletion, cleanup, report escalations.
Private object storage	Profile/chat image originals and approved derivatives.
FCM/APNs	Push notification delivery.

7.1 Django apps
config/
apps/
  accounts/       # custom User, auth identities, OTP challenges, sessions
  profiles/       # profile, photos, interests, visibility
  discovery/      # preferences, location, candidate service, impressions
  matching/       # swipes, matches, match service
  chat/           # conversations, messages, attachments, read state
  safety/         # blocks, reports, moderation actions, appeals
  notifications/  # devices, preferences, notification records
  operations/     # audit logs, deletion jobs, feature configuration
  common/         # base models, error format, permissions, idempotency
7.2 Flutter features
lib/
  app/                 # router, theme, localization
  core/                # API client, auth interceptor, secure storage, websocket
  features/
    auth/
    onboarding/
    profile/
    discovery/
    matches/
    chat/
    notifications/
    settings/
    safety/
  shared/              # models, widgets, utilities
Use Riverpod (or equivalent), go_router, Dio, json_serializable/freezed, flutter_secure_storage, web_socket_channel, firebase_messaging, image_picker, cached_network_image, and geolocator after checking current package maintenance and platform support. Keep domain rules out of widgets.
8. Complete logical data model
The accompanying SQL file provides a PostgreSQL reference schema with primary keys, foreign keys, check constraints, uniqueness constraints, and indexes. It is a baseline migration specification, not a replacement for Django-generated migrations. Use a custom Django user model before the first production migration.
Table	Purpose / important rules
users	Canonical account; phone, status, verification timestamps, consent versions, deletion timestamps.
auth_identities	Provider identity (phone/google); unique provider + provider subject; identity linking.
otp_challenges	Hashed OTP, destination, purpose, expiry, attempt count, consumed timestamp; never store raw OTP.
user_sessions	Hashed refresh token, device, expiry, revocation, rotation lineage.
profiles	Public profile fields, DOB privately, gender identity, bio, visibility, approval status.
discovery_preferences	Age range, distance, location mode, selected gender IDs, reciprocal preference flag.
user_locations	Private PostGIS geography point, source (GPS/manual), updated time; not public.
profile_photos	Private object keys, ordering, primary flag, moderation state, dimensions, size.
interests	Admin-maintained interest taxonomy.
profile_interests	Many-to-many selection; unique user + interest.
swipes	One current directional action per actor/target; idempotency key.
matches	Canonical ordered pair, status, ended_by, end reason; unique pair.
conversations	One-to-one with match.
messages	Conversation, sender, client idempotency key, type, body, sequence number, state.
message_attachments	Private object key, type, size, dimensions, moderation state.
conversation_user_state	Per-user read sequence, mute/archive state.
user_blocks	Directional block; unique blocker + blocked; users differ.
reports	Reporter, target, category, related match/message, status, priority, assigned moderator.
moderation_actions	Action type, reason, duration, moderator, related report, appeal status.
devices	Platform and push token per device, app version, revocation.
notification_preferences	Per-category preferences and message-preview choice.
notifications	Delivery state, category, minimal payload reference, retries.
audit_logs	Actor, action, target, request ID, timestamp, safe metadata.
data_deletion_jobs	Requested, processing, completed/failed state and retention-safe result.
discovery_impressions	Optional privacy-conscious exposure and rank version analytics.
outbox_events	Durable post-commit events for match/message/notification publication.

8.1 Important database invariants
    • Use UUID primary keys; timestamps are UTC timestamptz.
    • Phone number must be normalized; enforce uniqueness on the normalized identifier. For optional phone/email, use partial unique indexes or a normalized identity table.
    • User must not swipe, match, block, or report themselves.
    • Unique directional swipe per actor/target; unique idempotency key per actor.
    • Canonical match pair (user_low < user_high) and unique pair constraint; transaction service validates reciprocal likes.
    • Conversation has one unique match; match has exactly two participants logically enforced by canonical pair columns.
    • Message client idempotency unique per sender; sequence unique per conversation.
    • At most one active primary photo per user; active photo position unique per user.
    • Foreign keys use deliberate deletion policy; avoid cascading deletion of safety/audit/financial evidence without an approved retention rule.
    • Add indexes for discovery eligibility, swipe lookups, conversation sequence, report queue, and geo queries.
9. REST API specification
Base path: /api/v1/. JSON by default; media upload may use presigned URLs. All protected endpoints require access credentials and object-level authorization. The backend owns validation and state transitions.
Authentication
Method	Endpoint	Purpose
POST	/auth/otp/request	Request phone OTP; generic response; rate limited.
POST	/auth/otp/verify	Verify OTP; create/link session and account.
POST	/auth/google	Verify Google ID token server-side and issue app session.
POST	/auth/refresh	Rotate refresh token.
POST	/auth/logout	Revoke current session.
POST	/auth/logout-all	Revoke all sessions.
GET	/auth/sessions	List current user's active sessions.
DELETE	/auth/sessions/{session_id}	Revoke owned session.

Profile/onboarding
Method	Endpoint	Purpose
GET	/me	Current user summary and onboarding state.
GET	/me/profile	Own profile.
PATCH	/me/profile	Update allowed profile fields.
GET	/profiles/{user_id}	Public profile projection only.
GET	/interests	Active interest taxonomy.
PUT	/me/interests	Replace interests; maximum 10.
GET	/me/discovery-preferences	Read preferences.
PUT	/me/discovery-preferences	Update preferences.
POST	/me/photos/upload-url	Create pending upload and signed URL.
POST	/me/photos/{photo_id}/confirm	Queue validation/moderation.
PATCH	/me/photos/order	Reorder owned photos.
DELETE	/me/photos/{photo_id}	Remove owned photo.
PUT	/me/location	Update GPS/manual location; private.
DELETE	/me/location	Remove stored location.

Discovery/matching
Method	Endpoint	Purpose
GET	/discovery/feed?cursor=...&limit=...	Cursor-paginated eligible candidates.
POST	/swipes	Like/pass with client_action_id.
GET	/matches?cursor=...	List active matches.
GET	/matches/{match_id}	Read match if participant.
POST	/matches/{match_id}/unmatch	End match idempotently.

Chat
Method	Endpoint	Purpose
GET	/conversations?cursor=...	List current user's conversations.
GET	/conversations/{id}/messages?before=...&limit=...	Cursor-paginated history.
POST	/conversations/{id}/messages	Send text or reference approved image attachment.
POST	/conversations/{id}/read	Advance last_read_sequence.
DELETE	/messages/{id}	Delete own message where policy permits.
POST	/conversations/{id}/attachments/upload-url	Create private image upload.
POST	/conversations/{id}/attachments/{attachment_id}/confirm	Validate and moderate attachment.

Safety/settings
Method	Endpoint	Purpose
POST	/users/{user_id}/block	Block; stop discovery/messaging; end or restrict match per policy.
DELETE	/users/{user_id}/block	Unblock.
GET	/me/blocked-users	List own blocks.
POST	/reports	Report profile/message.
GET	/me/notification-preferences	Get preferences.
PATCH	/me/notification-preferences	Update preferences.
POST	/me/data-export	Request export.
POST	/me/deletion-request	Request account deletion.
GET	/me/deletion-request	Get deletion status.

Admin (staff-only)
Method	Endpoint	Purpose
GET	/admin/reports	Filter and paginate moderation queue.
GET	/admin/reports/{id}	Read assigned/authorized report.
POST	/admin/reports/{id}/assign	Assign case.
POST	/admin/reports/{id}/actions	Record moderation action.
POST	/admin/users/{id}/restrict	Apply justified restriction.
POST	/admin/users/{id}/reinstate	Reinstate with audit.
GET	/admin/health/summary	Operational metrics, no secret data.

9.1 API conventions
    • Success envelope: {data: ..., meta: {request_id: ...}}. Error envelope: {error: {code, message, fields?, request_id}}.
    • Use 200/201/202/204, 400, 401, 403, 404, 409, 422 (if standardized), 429, and 500 consistently.
    • Use opaque cursors rather than offsets for feeds and chat history.
    • Use Idempotency-Key or request UUID for swipe, message, and deletion submissions.
    • Never reveal whether a phone exists during OTP request; return a generic accepted response.
    • Public serializers must be explicit allowlists, not full model serializers.
    • Every list endpoint scopes the queryset to the current user's authorized records before serialization.
    • Set global DRF default permission to IsAuthenticated; explicitly mark only intended public endpoints as AllowAny.
10. WebSocket contract
Suggested endpoint: wss://api.example.com/ws/conversations/{conversation_id}/. Authenticate using a short-lived, single-use connection ticket obtained through REST, or another reviewed mechanism. Do not put long-lived bearer tokens in URLs.
10.1 Client events
Event	Payload	Rule
message.send	client_message_id, type, body or attachment_id	Same authorization/validation as REST; idempotent.
message.read	last_read_sequence	Monotonic; cannot exceed latest persisted sequence.
ping	nonce/time	Connection health only.

10.2 Server events
Event	Payload essentials
message.created	event_id, message_id, conversation_id, sender_id, sequence_number, created_at
message.status_changed	message_id, status
message.read_updated	user_id, last_read_sequence
match.ended	match_id, reason category if appropriate
conversation.updated	conversation_id, last_message_at
connection.error	stable error code; no sensitive internals

Assume events can be duplicated or arrive out of order. Clients deduplicate by event_id/message_id and reconcile from REST after reconnect. Authorization is checked at connect and again for state-changing events; restrictions must be able to close active sockets.
11. Core transaction algorithms
11.1 Swipe/match
1. Authenticate actor; validate target != actor; rate-limit.
2. Begin transaction.
3. Check idempotency record; if found, return stored result.
4. Lock the canonical user pair in deterministic order.
5. Re-check account, visibility, preference, block, and moderation rules.
6. Upsert the directional swipe state.
7. If action is Like and reciprocal Like exists:
   a. create/get canonical unique match;
   b. create/get one conversation;
   c. store idempotent result;
   d. insert outbox event.
8. Otherwise store result (liked/passed).
9. Commit; async worker publishes event and push notification.
The lock strategy must work even before a match row exists. Use a stable pair-lock table/advisory lock or another tested database locking approach. Database uniqueness is the final defense against duplicates. Do not call push providers while holding a transaction open.
11.2 Message send
1. Authenticate; load conversation and match.
2. Check participant, active match, block, account state, restrictions.
3. Validate type/body/attachment ownership and moderation approval.
4. Begin transaction and deduplicate (sender, client_message_id).
5. Allocate next conversation sequence atomically.
6. Persist message and update conversation summary.
7. Insert outbox event; commit.
8. Return persisted message; worker publishes WebSocket/push events.
12. Non-functional requirements
Area	Target / requirement
API latency	Initial target p95 ≤300 ms for ordinary reads and swipe writes, excluding external providers.
Discovery latency	Initial target p95 ≤700 ms at agreed test load.
Realtime	Target p95 ≤1 second from persistence to connected recipient event under test load.
Availability	Design target 99.9% monthly after operational maturity; validate against budget and team capacity.
Client quality	Target ≥99.5% crash-free sessions during beta; improve based on actual metrics.
Security	TLS, least privilege, object-level authorization, secure token storage, rate limits, secret management.
Privacy	Private exact location; approved media only; minimal push payload; retention and deletion policy.
Accessibility	Screen-reader labels, scalable text, contrast, non-gesture alternatives to swipe.
Localization	Localization-ready; launch language(s) explicitly chosen; use locale-aware dates/plurals.
Recovery	Automated backups, tested restore, defined RPO/RTO, queue retry/dead-letter monitoring.

Targets are initial engineering goals, not guarantees. Establish reference devices, network conditions, concurrency, data volume, and measurement method before sign-off.
13. Security and privacy requirements
    • Use HTTPS in production and secure service-to-service connectivity where needed.
    • Use Django's password/security features for any staff or optional password auth; no plaintext secrets.
    • Verify Google tokens on the backend and validate issuer, audience, signature, expiry, and subject.
    • Hash OTPs and refresh tokens at rest; rotate secrets; expire challenges and sessions.
    • Apply global and per-endpoint throttling; protect OTP, login, swipe, message, upload, report, and export routes.
    • Use explicit DRF permissions and scoped querysets; never rely on UUID secrecy.
    • Validate uploads by content, size, and dimensions; re-encode and strip EXIF; store privately.
    • Redact OTPs, tokens, exact coordinates, and raw message bodies from routine logs.
    • Audit staff access to sensitive records and all moderation actions.
    • Publish retention policy for profiles, photos, messages, reports, audit logs, and deletion jobs.
    • Do not collect contacts or upload address books in MVP.
    • Complete Bangladesh legal/privacy review and Apple/Google user-generated-content policy review before public launch.
14. Admin and moderation operations
Module	Minimum features
User operations	Search by internal ID; inspect account status/verification; revoke sessions; restrict/reinstate with reason.
Report queue	Filter by priority/status/category, assign moderator, view permitted evidence, resolve/escalate.
Content moderation	Photo pending/rejected states, safety review, removal and appeal workflow.
Audit	Actor, action, target, timestamp, request ID, safe metadata; no silent history editing.
Operations	Queue backlog, API health, provider failure rates, backup status, error trends.

15. Testing and acceptance criteria
Test ID	Acceptance criterion
AC-AUTH-01	A valid OTP creates/authenticates the correct account; expired, wrong, reused, or over-attempt OTP is rejected.
AC-AUTH-02	A forged/expired/wrong-audience Google token is rejected; a valid token resolves to the correct provider subject.
AC-AUTH-03	OTP request does not disclose whether the phone is registered; limits apply across repeated requests.
AC-PROF-01	Incomplete, underage, hidden, suspended, or unapproved profiles never appear in discovery.
AC-PROF-02	Public profile response contains only allowlisted fields and never includes DOB, phone, email, exact coordinates, or moderation notes.
AC-MEDIA-01	Malformed image, wrong MIME signature, oversized file, and rejected image are never publicly served.
AC-MEDIA-02	Approved images have EXIF/GPS metadata removed and are served through authorized/time-limited URLs.
AC-DISC-01	Discovery excludes self, blocks in both directions, previously acted-on profiles, and ineligible accounts.
AC-DISC-02	GPS-denied user can use manual area mode and the UI accurately explains the limitation.
AC-DISC-03	Feed cursor pagination does not produce duplicates under normal concurrent changes and does not expose coordinates.
AC-MATCH-01	One Like alone does not create a match; reciprocal Likes create exactly one match and one conversation.
AC-MATCH-02	Concurrent reciprocal likes from separate requests create one match; retries return the original result.
AC-CHAT-01	Only active participants can read/send; guessed conversation UUID does not grant access.
AC-CHAT-02	Duplicate client_message_id produces one persisted message; sequence numbers are unique and ordered per conversation.
AC-CHAT-03	A message is acknowledged only after persistence; network retry reconciles without duplicate messages.
AC-CHAT-04	Image attachments are private and cannot be sent until validation/moderation permits it.
AC-SAFE-01	Blocking prevents future discovery and messages in both directions; active connection is closed/restricted.
AC-SAFE-02	Report is private, appears in authorized moderation queue, and records status/action history.
AC-DELETE-01	Deletion removes user from discovery immediately, revokes sessions, schedules data/media cleanup, and exposes status.
AC-NOTIF-01	Invalid push tokens are disabled; notification preferences are honored; deep links re-check permissions.
AC-OPS-01	Critical outbox events survive worker interruption and are eventually retried without duplicate business effects.
AC-OPS-02	Backup can be restored in a documented test; health alerts fire for sustained failures.

15.1 Mandatory adversarial integration tests
    • Two users like each other at exactly the same time.
    • Block arrives while a Like or message request is in flight.
    • A message is retried after server commit but before client receives response.
    • User A attempts to read User B's conversation by guessing UUID.
    • WebSocket remains open after suspension/unmatch/block.
    • Image upload completes after deletion request.
    • OTP is requested repeatedly from multiple IPs/devices.
    • Manual location and GPS location are switched repeatedly.
    • Moderators concurrently update the same report.
    • Redis/worker outage occurs after database commit.
    • Notification arrives after logout or account restriction.
    • Deleted account attempts token refresh.
16. Implementation backlog and release gates
Priority / phase	Scope	Exit criterion
P0 / Sprint 0	Repository, environment, CI/CD, ADRs, OpenAPI skeleton, logging, secrets, database migrations	Build/test pipeline green; staging deployment repeatable.
P0 / Sprint 1	Custom User, phone normalization, OTP provider adapter, OTP challenge storage, Google token verification, sessions/refresh rotation	Auth acceptance tests pass; throttling and enumeration tests pass.
P0 / Sprint 2	Profile, DOB/18+ gate, interests, discovery preferences, onboarding state, profile serializers	Only valid completed profiles can become discoverable.
P0 / Sprint 3	Private upload flow, media processing, EXIF stripping, photo moderation state, deletion cleanup	Unapproved files never public; image pipeline monitored.
P0 / Sprint 4	Private location model, PostGIS index, manual-area fallback, candidate eligibility query, cursor feed	Eligibility and location privacy tests pass.
P0 / Sprint 5	Swipes, idempotency, pair lock, reciprocal-like transaction, match/conversation creation, outbox	Concurrency test proves one match per pair.
P0 / Sprint 6	Messages, attachments, sequence allocation, pagination, conversation permissions, REST send/read	Authorization, idempotency, and ordering tests pass.
P0 / Sprint 7	Channels auth, WebSocket events, reconnect/reconcile, FCM/APNs notifications	Duplicate/out-of-order events handled; push preference tests pass.
P0 / Sprint 8	Block, report, moderation admin, account restriction, deletion/export, audit logs	Safety flows and staff access controls pass.
P0 / Sprint 9	Flutter polish, accessibility, localization readiness, offline/error states, analytics	Critical user journeys pass on target devices.
P0 / Sprint 10	Security review, load test, restore drill, app-store compliance review, beta runbook	Release gate signed by product, engineering, QA, and safety owner.
P1 after launch	Improve ranking, interest compatibility, richer moderation tools, verified profiles, optional advanced features	Only after MVP usage and safety baselines are measured.

17. Release checklist
    • Product and legal review of Terms, Privacy Policy, community guidelines, age controls, and deletion policy.
    • Google sign-in OAuth configuration and OTP provider delivery verified in target market.
    • Production secrets, TLS, backups, restore drill, monitoring, and on-call ownership configured.
    • No public unmoderated upload path; signed URLs expire and private buckets are not listable.
    • Rate limits and abuse handling tested under realistic conditions.
    • Concurrency tests pass for matches and message sequence allocation.
    • All APIs have explicit permissions and object-level tests.
    • Android/iOS permissions are requested just in time and can be declined without app lockout.
    • Data deletion and report escalation are operational, not just UI screens.
    • App-store UGC, privacy, and safety requirements reviewed before submission.
    • Beta cohort, feedback channel, incident response plan, and rollback procedure documented.
18. Open implementation decisions
Decision	Recommended baseline	Must resolve by
OTP provider	Select provider based on Bangladesh delivery, sender registration, cost, and reliability.	Sprint 1
Launch languages	Bangla + English readiness; confirm which languages ship on day one.	Design sign-off
Manual location taxonomy	Admin-managed divisions/districts/cities/areas; do not free-text match alone.	Sprint 2
Photo moderation	Choose provider/workflow and human-review SLA.	Before media release
Message retention	Publish duration and evidence exceptions; align legal and safety needs.	Before beta
Underage assurance	Choose risk-based verification/escalation process; age gate alone is insufficient.	Before public launch
Launch region	Choose controlled beta area and minimum candidate density threshold.	Beta plan
Performance test load	Set target concurrent users, sockets, messages/sec, and candidate count.	Before release gate

19. Reference documentation
Use current supported versions of Django and Django REST Framework. Review the official references below during implementation:
    • Django REST Framework — Permissions: https://www.django-rest-framework.org/api-guide/permissions/
    • Django REST Framework — Authentication: https://www.django-rest-framework.org/api-guide/authentication/
    • Django — Model constraints: https://docs.djangoproject.com/en/6.0/ref/models/constraints/
    • Django — Security: https://docs.djangoproject.com/en/6.0/topics/security/
This SRS is an engineering baseline, not legal advice or a guarantee of app-store approval. Confirm current documentation, platform policies, Bangladesh legal requirements, and package versions at implementation time.