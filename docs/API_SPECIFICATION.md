# API specification

Status: proposed v1 contract, 2026-09-16. No endpoints are deployed. Names and typed fields refer to [database schema](DATABASE_SCHEMA.md). Implement machine-readable OpenAPI and contract fixtures in P1; this is the normative design.

## Transport and principal

HTTPS JSON API under `/v1`. Firebase SDK owns sign-in, password reset and token refresh; the backend never accepts a password. Each business request sends `Authorization: Bearer <Firebase ID token>` and an App Check token in `X-Firebase-AppCheck`. These are descriptions of headers, not credentials. Reject invalid issuer/audience/project, expiry or disabled/deleting accounts. App Check supplements authentication; it does not prove ownership.

Do not accept a UID to select a tenant. All `/me` and nested paths resolve from the authenticated principal. A missing object and an object outside the principal's scope both return 404. No generic collection/path passthrough. Server code uses typed collection allowlists.

Return `Cache-Control: private, no-store` for sensitive endpoints. Client caching is the explicit encrypted app cache. Strict JSON validation rejects unknown properties, malformed IDs, unexpected enum values, invalid Unicode/lengths and non-finite numbers. Ordinary JSON body cap 64 KiB; log bulk cap 50 operations and 256 KiB; chat text cap 8,000 characters; page size default 50 and maximum 100. These are initial application policies, not provider limits.

## Common envelopes and concurrency

Success: `data:object|list`, `meta:{requestId:string, serverTime:timestamp, nextCursor:string?, sourceThroughSeq:int?, dataEpoch:int?}`. A paginated result never exposes unbounded collections. Error: `error:{code:string, message:string, requestId:string, retryable:bool, fieldErrors:list<{field,code}>?}`. No stack traces, prompts or provider response bodies.

Mutations require `Idempotency-Key` (stable UUID), `operationCreatedAt:timestamp`, and, for updates/deletes, `baseRevision:int`. Creates use revision 0 and a stable entity ID. Server-generated timestamps, UID, roles, aggregate values and evidence fields cannot be submitted as editable fields. Same key + same canonical body returns the prior result; same key + different body returns 409 `IDEMPOTENCY_CONFLICT`. API checks account/consent status before replaying a receipt.

Commit entity, feed, receipt and job markers atomically. Mutations older than 30 days return 409 `RECONCILIATION_REQUIRED`; a future timestamp outside a five-minute tolerance returns 422. A stale base revision returns 409 `REVISION_CONFLICT` with current revision and current same-user entity. Do not auto-merge two changes to the same numerical record. `DELETE` returns a tombstone reference and acknowledged sequence. A previously deleted ID cannot be recreated by replay.

| HTTP | Code examples | Client behavior |
| --- | --- | --- |
| 400/415 | MALFORMED_REQUEST / UNSUPPORTED_MEDIA_TYPE | Fix request, do not retry automatically |
| 401 | AUTH_REQUIRED / TOKEN_EXPIRED | Refresh once through Firebase; then require sign-in |
| 403 | ACCOUNT_DISABLED / CONSENT_REQUIRED / ATTESTATION_FAILED | Explain recovery; do not loop retries |
| 404 | NOT_FOUND | Remove stale link or refresh parent |
| 409 | REVISION_CONFLICT / REQUEST_IN_PROGRESS | Resolve conflict or poll existing operation |
| 410 | CURSOR_EXPIRED / PROPOSAL_EXPIRED | Resynchronize or regenerate proposal |
| 413/422 | PAYLOAD_TOO_LARGE / VALIDATION_FAILED | Preserve draft and show field guidance |
| 423 | EXPORT_SNAPSHOT_BUSY | Short Retry-After; keep ordinary mutation in local outbox without claiming server commit; privacy erasure bypasses barrier |
| 429 | RATE_LIMITED / BUDGET_EXHAUSTED | Respect Retry-After; never retry tight loop |
| 503/504 | DEPENDENCY_UNAVAILABLE / DEADLINE_EXCEEDED | Bounded retry only with idempotency, preserve drafts |

## Identity, profile and privacy

| Method and path | Request | Response and invariants |
| --- | --- | --- |
| POST `/me/bootstrap` | eligibility declaration, locale, timezone, unit preferences, consent choices | Idempotent user/profile/settings creation after Firebase sign-in; 201 first time, 200 existing |
| GET `/me` | None | Profile, settings, lifecycle, capabilities and policy versions; no secrets |
| PATCH `/me/profile` | Allowed profile fields + baseRevision | Updated profile, revision, committed sequence |
| PATCH `/me/settings` | Allowed settings + baseRevision | Updated settings; cannot grant AI consent implicitly |
| POST `/me/consents` | category, granted, policyVersion | Append event and immediately update effective gate; revocation schedules context/session invalidation |
| POST `/me/exports` | format: JSON or CSV, requested date scope | 202 privacy job ID; recent authentication required |
| POST `/me/erasures` | scope: record/range/category, range or typed IDs | 202 deletion job; immediate logical exclusion, recent authentication required |
| DELETE `/me` | explicit confirmation + recent auth | 202 deletion receipt; disables future business access and stops voice |
| GET `/me/privacy-jobs/{id}` | None | Redacted job status; after account disable, a narrowly scoped receipt capability can read only this job status |
| GET `/me/artifacts/{id}/download` | None | Short-lived single-artifact access grant; authorize anew, no permanent public URL |

Implemented preference-write envelopes use `operationId`, `operationCreatedAt`, `baseRevision` and `changes` for profile/settings; consent writes use the same metadata plus `category`, `granted` and `policyVersion`. `baseRevision` is the profile/settings revision or account `consentVersion`. Responses include `revision`, `committedSeq` and a current account projection. Retried operation IDs require identical bodies. The change feed carries account-change markers and a current account projection, without treating those markers as tracking records. See generated OpenAPI for strict request schemas.

Recent authentication means a server-checked `auth_time` within five minutes, proposed policy. Account deletion cannot rely on the client deleting the Firebase user first. Issue the minimal status receipt before revoking sessions. Export snapshots require a consistent cutoff; see [security export workflow](SECURITY_MODEL.md). During the short export snapshot barrier, ordinary mutations return 423 and stay in the client's existing outbox; the server does not introduce another queue of uncommitted health payloads. Barrier expiry is checked transactionally so a crashed export cannot indefinitely block tracking.

## Tracking and planning resources

Generic contract is a documentation shorthand. Implementation must register a separate typed schema/use case for every resource below, not permit arbitrary Firestore paths.

| Resource route `/me/{resource}` | Entity payload | Supported filters |
| --- | --- | --- |
| `goals` | Goal editable fields | status, metric |
| `weight-logs` | Weight log fields | from, to |
| `body-measurements` | Body measurement fields | from, to, site |
| `food-logs` | Food log with bounded items | from, to, meal |
| `saved-foods` | Food item template | normalized name prefix |
| `hydration-logs` | Hydration log | from, to |
| `activity-logs` | Activity interval | from, to, source |
| `exercise-logs` | Workout interval | from, to, type |
| `sleep-logs` | Sleep interval | from, to, kind |
| `mood-logs` | Mood scale/rating/tags | from, to |
| `habits` | Habit + same-user schedule reference | status |
| `habit-logs` | Habit occurrence/status/quantity | habitId, from, to |
| `daily-check-ins` | Local date, answers, linked log IDs | from, to |
| `schedules` | Restricted recurrence and timezone fields | status, from, to |
| `reminders` | Same-user schedule, subject and delivery mode | enabled |

Each supports GET list, GET `/{id}`, POST create, PATCH `/{id}`, DELETE `/{id}` with revision and idempotency rules. Check-in IDs are local dates; habit-log IDs derive from a validated occurrence. Range lists use a half-open UTC interval or explicit date interval, never an ambiguous mix; response declares interpretation. Default list range is the last 30 days and maximum interactive range 366 days; older history is accessible through date windows or export. Cursor is opaque, authenticated, bound to UID + route + filters and includes ordering tie-break ID.

Bulk synchronization: POST `/me/sync/mutations`, list of at most 50 operations with `operationId`, `entityType`, `entityId`, `action`, `baseRevision`, `operationCreatedAt`, `payload`. Return per-operation success/conflict/error, not misleading all-or-nothing success. Each operation is atomic; dependent operations are ordered. Habit/schedule composite creation may use a dedicated atomic command with two typed payloads. Outbox never assumes HTTP 200 means every item succeeded.

## Download synchronization and bootstrap

GET `/me/sync/changes?cursor=...&limit=...` returns `{changes:[{seq,entityType,entityId,revision,operation,entity?}], nextCursor, headSeq, minimumAvailableSeq, dataEpoch}`. Change metadata may point to a newer entity version; clients only apply revisions newer than their local confirmed version. Tombstones win over older cached data. Repeated change pages are safe. Capture headSeq on first page and page through that bound before continuing.

GET `/me/sync/snapshot` starts a bounded snapshot session and returns a snapshot ID, start sequence and page cursor. Subsequent calls with snapshot ID stream every allowed live entity in deterministic entity-type/ID order. Do not claim Firestore provides an arbitrarily long cross-request snapshot: the rebuild algorithm is a baseline enumeration plus replay of all changes after the captured start sequence. Replaying corrects mutations during enumeration, including new IDs that sort before the page cursor. If the change feed has expired during enumeration, restart. Client atomically installs the baseline and replayed changes while preserving pending drafts separately. Server caps snapshot lifetime to one hour. Changes feed must include all client-visible resource mutations, including server summaries and memory updates.

## Analytics, reports and notifications

| Method and path | Contract |
| --- | --- |
| GET `/me/dashboard?date=...` | Bounded daily projection with coverage, pending rebuild indicators, source sequence and computation timestamp |
| GET `/me/progress?period=...&from=...&to=...` | Versioned deterministic summaries, freshness and timezone; return stale status rather than fabricated current data |
| POST `/me/reports` | Period and format; 202 job, uses confirmed data at cutoff; AI interpretation opt-in |
| GET `/me/reports/{id}` | Metadata/content and artifact availability |
| PUT `/me/devices/{id}` | Platform, FCM token, permission, app version; no other user's device takeover |
| DELETE `/me/devices/{id}` | Revoke token and server reminder targeting; logout calls this when online |
| POST `/me/devices/{id}/schedule-ack` | Reminder IDs/revisions and local scheduling outcome; prevents false assumptions of local scheduling |
| GET `/me/notifications` | Paginated private inbox |
| PATCH `/me/notifications/{id}` | `read:true`; server sets readAt |

## Text coaching and memory

| Method and path | Contract |
| --- | --- |
| POST `/me/conversations` | Optional bounded title; returns conversation ID |
| GET `/me/conversations` | Cursor page of active/archived conversations |
| GET `/me/conversations/{id}/messages` | Cursor page, completed/interrupted state and evidence; no unbounded history |
| POST `/me/conversations/{id}/turns` | `messageId`, `text`, optional typed intent; validates consent and ownership; durable request record and usage reservation |
| GET `/me/ai-requests/{id}` | State and resulting assistant message ID; reconnect does not regenerate |
| POST `/me/ai-requests/{id}/cancel` | Best-effort generation cancellation; billed usage may remain; never marks incomplete output completed |
| DELETE `/me/conversations/{id}` | Immediate exclusion and asynchronous children/summary/evidence invalidation |
| GET `/me/memories` | Visible candidates/active memories, provenance and evidence |
| POST `/me/memories` | User-authored or explicitly confirmed statement, category and permitted reference; server validates provenance |
| PATCH `/me/memories/{id}` | Correction, confirmation or dispute with baseRevision; cannot promote an AI observation through a generic field update |
| DELETE `/me/memories/{id}` | Forget immediately, invalidate context and prevent re-extraction from retained sources unless user opts back in |
| GET `/me/observations` | Labeled hypotheses/patterns with evidence, coverage, expiry |
| PATCH `/me/observations/{id}` | Dismiss or request correction; no direct fact promotion |
| GET `/me/recommendations` | Relevant unexpired suggestions |
| PATCH `/me/recommendations/{id}` | Accept/dismiss/feedback, with no automatic domain mutation |
| POST `/me/action-proposals/{id}/confirm` | Confirm exact displayed payload and revision; revalidate scope and apply once |

Turn response uses SSE over an authenticated HTTP POST: `accepted` (request ID), `progress` (safe state enum), `message` (completed validated answer), `completed` or `failed`. Initial production design buffers generated prose until safety and evidence checks pass; no unsafe partial text is displayed merely to improve first-token latency. No assumption that POST SSE automatically resumes: poll the request after disconnect. Server deadline 30 seconds; unresolved external outcomes enter `unknown` state for reconciliation, not automatic double billing. No provider-history object is required.

## Voice contracts

POST `/me/voice-sessions` takes conversation ID, locale and consent acknowledgment. Returns application session ID, controller endpoint and a short-lived single-use controller ticket bound to UID/session/device. It does not return an OpenAI permanent key. Ticket is held in memory and sent in an authorization header, not a URL query.

Controller WSS `/v1/voice/sessions/{id}/events` requires authenticated upgrade with the single-use ticket. Its first typed `connect` message carries the SDP offer, maximum 64 KiB. The same connection-owning handler validates policy, establishes the provider call, stores private call ID, attaches sideband and emits `ready` with the SDP answer when control is ready. Later application events are `caption`, `interrupted`, `usage_warning`, `action_proposal`, `ended`, `error`. After connect, client commands are limited to typed `mute`, `interrupt`, `end` and heartbeat. No arbitrary session-update or tool-result passthrough. Keeping signaling and lifecycle on one request avoids relying on Cloud Run affinity between separate HTTP and WebSocket requests.

POST `/me/voice-sessions/{id}/end` is idempotent and requests server hangup. GET `/me/voice-sessions/{id}` provides status. Reconnect creates a new provider call with verified context; it never replays unsent audio. See [voice architecture](VOICE_ARCHITECTURE.md) for session limits and control-plane recovery.

## Internal routes and initial rate policy

`/internal/jobs/tick`, `/internal/notifications/tick`, `/internal/reconcile` require scheduler/service authentication distinct from user auth; validate timing and lease tokens, reject public use. Do not expose arbitrary user/collection actions through these routes. Provider webhooks, if introduced, require verified signature, timestamp tolerance and replay deduplication.

Initial limits per active UID: ordinary reads 120/minute, mutations 60/minute, text turns 10/minute and one active generation per conversation, voice one active session and three starts/minute, exports one active and three/day. Add coarse edge/IP protection with privacy-preserving short retention. Persistent Firestore reservations and transactionally checked quotas replace in-process counters. Product daily spend caps are approved in P0; enforce fail-closed for new AI work when budget state is unavailable. Tracking remains usable offline.
