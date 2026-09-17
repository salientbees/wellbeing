# Firestore and storage schema

Status: proposed v1, 2026-09-16. Canonical persisted names for the blueprint. See [API contracts](API_SPECIFICATION.md), [security](SECURITY_MODEL.md) and [analytics](ANALYTICS_AND_INSIGHTS.md).

## Types, ownership and invariants

Notation: `string`, `bool`, `int`, `number` (finite numeric value), `timestamp` (Firestore UTC timestamp), `date` (ISO local calendar date), `enum`, `map`, `list<T>`, `ref` (typed same-user entity ID, not arbitrary Firestore path). `?` means optional; absent is distinct from zero. API timestamps are RFC 3339 UTC strings. Do not store NaN/infinity, localized formatted numbers or unbounded arrays.

All user-owned entities live under `users/{uid}`. UID is the Firebase Authentication subject. Relationships resolve under that UID; foreign entity IDs from another UID never authorize access. Backend-only operational collections carry `ownerUid` when applicable. Firestore and Storage client rules deny all business access; Firebase Admin bypasses those rules, so backend repository scoping and IAM are critical.

Every user entity has `schemaVersion:int`, `revision:int`, `createdAt:timestamp`, `updatedAt:timestamp`, `deletedAt:timestamp?`. Server assigns revision and timestamps. User-owned mutable entities also have `lastOperationId:string` and `syncSeq:int`. Client-created IDs are random UUIDs without health information. Soft deletion is a short-lived propagation mechanism, not permanent erasure. Strip sensitive payloads during erasure and retain only ID/revision/deletion metadata in sync tombstones; do not keep health values for the full feed window merely to support synchronization.

All log entities additionally carry `occurredAt:timestamp`, `localDate:date`, `timeZone:string` (IANA), `utcOffsetMinutes:int`, `source:enum(manual,healthkit,healthConnect,import)`, `sourceRecordId:string?`, `sourceDeviceId:string?`, `quality:enum(userReported,deviceReported,estimated)`, and optional bounded `note:string`. Historical local dates retain their recorded timezone unless the user explicitly corrects the record. An imported device reading is not medically verified.

Canonical units: weight kg, circumference cm, fluid mL, distance m, duration seconds, energy kcal, nutrients g. Save original value/unit where a conversion would otherwise lose user-entered precision. Display conversion does not rewrite history. Define engineering bounds per metric in versioned validation schemas; bounds detect malformed input, not clinical safety. Extreme but plausible entries require confirmation rather than silent clamping.

## Retention classes

| Code | Proposed policy |
| --- | --- |
| R1 | User-authored tracking/profile/goals kept until user deletion or account deletion; offer optional auto-delete windows; no indefinite copied history in logs |
| R2 | Conversation messages default 90 days; user may choose shorter or keep-until-deleted; conversational summaries expire with their source scope |
| R3 | Active user-confirmed memory retained until forgotten/expired; AI observations default 30 days, pending candidates 7 days; see memory review rules |
| R4 | Derived summaries recomputable, retain while corresponding source period is retained; erase/rebuild on source deletion |
| R5 | Notification inbox/delivery metadata 30 days; device tokens removed on logout/revocation or staleness review |
| R6 | Sync feed/tombstones 30 days; operation receipts 30 days; reject operations older than replay window and require reconciliation |
| R7 | Job payload only while required; terminal jobs 7 days; content-free operational/security metadata 30/90 days respectively |
| R8 | Export/report artifacts 24 hours by default, short-lived access grants; raw voice audio not stored by Wellbeing |

These are product proposals requiring privacy approval, not statements of statutory retention. Expired data is excluded by application reads immediately; Firestore TTL cleanup is eventual and is not the authorization or erasure mechanism. Full deletion details, backups and provider limits are in [security](SECURITY_MODEL.md).

## Core entities

Every row inherits common fields, UID ownership and deny-all client access. Index labels refer to the query catalog below. Server validation restricts user-editable fields; clients never set derived fields.

| Path beneath `users/{uid}/` | Purpose and key fields with types | Relationships and constraints | Index / retention / security |
| --- | --- | --- | --- |
| User root itself | Account lifecycle: `status:enum(active,deleting,disabled)`, `onboardingVersion:int`, `consentVersion:int`, `dataEpoch:int` | Same UID as Auth; do not duplicate email/password; `dataEpoch` invalidates contexts on erasure/correction | Point read; R1; server-only lifecycle changes |
| `profiles/main` | `preferredName:string?`, `locale:string`, `timeZone:string`, `unitPreferences:map`, `coachingTone:enum`, `ageEligible:bool` | One profile; avoid exact DOB, address, sex or medical history unless separately justified | Point read; R1; no email in AI context |
| `settings/main` | `theme:enum`, `reduceMotion:bool`, `hiddenMetrics:list<enum>`, `weekStartsOn:int`, `retentionPreferences:map`, `notificationPreferences:map`, `aiPreferences:map` | Bounded known keys; changes to consent use dedicated consent API | Point read; R1; cannot grant server privileges |
| `consents/{id}` | `category:enum(aiProcessing,memory,analytics,crashReports,healthImport)`, `granted:bool`, `policyVersion:string`, `recordedAt:timestamp`, `method:enum` | Server records append-only consent events; current grants derived in profile service | I2; R1 with minimal consent audit policy; never sent to analytics |
| `goals/{id}` | `metric:enum`, `direction:enum(increase,decrease,maintain,complete)`, `baseline:number?`, `target:number?`, `lowerBound:number?`, `upperBound:number?`, `unit:enum?`, `startDate:date`, `targetDate:date?`, `status:enum`, `milestones:list<map>` | Maintain goals require ordered lower/upper bounds; at most 20 bounded milestones; self-chosen targets; changes increment revision | I3; R1; no automatic AI edits |
| `goalRevisions/{id}` | `goalId:ref`, `effectiveFrom:timestamp`, `baseline:number?`, `target:number?`, `lowerBound:number?`, `upperBound:number?`, `status:enum`, `reason:string?` | Snapshot at each goal change; historical progress uses effective target/range | I4; R1; backend-authored, included in deletion |
| `weightLogs/{id}` | Common log + `weightKg:number`, `originalValue:number?`, `originalUnit:enum?` | Multiple records/day allowed; daily chart representative rule in analytics | I1; R1; numerical validation |
| `bodyMeasurements/{id}` | Common log + `site:enum(waist,hip,chest,arm,thigh,other)`, `side:enum?`, `circumferenceCm:number`, `customSite:string?` | One site per record; no body image requirement | I1/I5; R1; notes excluded from indexing |
| `foodLogs/{id}` | Common log + `meal:enum`, `items:list<FoodItem>`, `nutritionStatus:enum(complete,partial,unknown)` | Maximum 30 items; FoodItem fields below; estimates are explicit | I1; R1; no provider photo retention by default |
| `hydrationLogs/{id}` | Common log + `volumeMl:number`, `beverageType:enum` | Positive volume; corrections by revision, not negative compensations | I1; R1; no inferred medical target |
| `activityLogs/{id}` | Common log + `startAt:timestamp`, `endAt:timestamp`, `steps:int?`, `distanceM:number?`, `activeSeconds:int?`, `sourceGroup:string` | Interval; distinguish whole-day cumulative import from incremental sample; source dedup policy required | I1/I6; R1; imported IDs hashed/scoped |
| `exerciseLogs/{id}` | Common log + `type:enum`, `startAt:timestamp`, `endAt:timestamp`, `durationSeconds:int`, `effort:int?`, `energyKcal:number?` | User-reported effort scale 1–10; energy estimates labeled; don't add workout steps to daily steps | I1; R1; no intensity prescription |
| `sleepLogs/{id}` | Common log + `startAt:timestamp`, `endAt:timestamp`, `awakeSeconds:int?`, `kind:enum(main,nap)`, `quality:int?` | Assign localDate to wake date; reject end before start; quality 1–5 | I1/I6; R1; do not infer sleep disorder |
| `moodLogs/{id}` | Common log + `rating:int`, `scaleVersion:string`, `tags:list<string>` | Rating 1–5, ordinal not diagnostic; bounded optional tags | I1; R1; highest sensitivity; no telemetry payload |
| `habits/{id}` | `name:string`, `targetQuantity:number`, `unit:enum`, `scheduleId:ref`, `status:enum`, `effectiveFrom:date` | Changes versioned; archived/pause intervals retained for denominators | I3; R1; same-user schedule |
| `habitRevisions/{id}` | `habitId:ref`, `effectiveFrom:date`, `status:enum`, `targetQuantity:number`, `scheduleId:ref`, `scheduleRevision:int` | Immutable effective-dated snapshots including pause/resume; backend-authored | Parent/effectiveFrom index; R1; erase with habit |
| `habitLogs/{id}` | Common log + `habitId:ref`, `occurrenceId:string`, `status:enum(done,partial,skipped)`, `quantity:number?` | Deterministic habit + occurrence ID enforces one completion record; explicit not-done differs from no log | I7; R1; parent ownership checked |
| `dailyCheckIns/{date}` | `localDate:date`, `timeZone:string`, `answers:map`, `linkedLogIds:list<ref>` | One per date; maximum 10 typed answers; references mood/sleep rather than duplicating measured values | I8; R1; free text excluded from analytics |
| `schedules/{id}` | `kind:enum(oneOff,daily,weekly)`, `localTime:string`, `weekdays:list<int>?`, `startDate:date`, `endDate:date?`, `timeZone:string`, `zoneMode:enum(fixed,followProfile)`, `status:enum`, `nextOccurrenceAt:timestamp?` | Explicit wall-clock recurrence, skip dates and revision; references are same user | I3; R1; server calculates next occurrence |
| `scheduleRevisions/{id}` | `scheduleId:ref`, `effectiveFrom:timestamp`, `definition:map`, `skipDates:list<date>` | Typed recurrence snapshot; skipDates capped at 100 per revision; historical due occurrences reproducible | Parent/effectiveFrom index; R1; server-authored |
| `reminders/{id}` | `scheduleId:ref`, `subjectType:enum`, `subjectId:ref?`, `deliveryMode:enum(local,push)`, `primaryDeviceId:ref?`, `enabled:bool`, `nextDueAt:timestamp?` | One delivery owner per occurrence; pending schedule changes cannot activate push | I9; R1; generic templates only |
| `notifications/{id}` | `occurrenceKey:string`, `kind:enum`, `templateId:string`, `target:map`, `status:enum`, `createdAt:timestamp`, `readAt:timestamp?`, `expiresAt:timestamp` | In-app history, safe route targets; no health values in external payload | I10; R5; server creates, owner read acknowledgment via API |

`FoodItem`: `name:string`, `quantity:number`, `portionUnit:enum`, `grams:number?`, `energyKcal:number?`, `proteinG:number?`, `carbohydrateG:number?`, `fatG:number?`, `fiberG:number?`, `source:enum(manual,label,licensedDatabase,estimate)`, `sourceId:string?`, `basis:enum(perPortion,per100g)`. Persist normalized consumed totals alongside original basis so later database edits do not change history. Unknown nutrients remain null/absent. `savedFoods/{id}` reuses the same bounded item schema for user templates (name query I2, R1); template edits never rewrite consumed entries.

## AI and derived entities

| Path beneath `users/{uid}/` | Purpose and key fields with types | Relationships / indexes / retention / security |
| --- | --- | --- |
| `conversations/{id}` | `title:string?`, `status:enum(active,archived,deleting)`, `lastMessageAt:timestamp`, `summary:string?`, `summarySourceThroughSeq:int?`, `summaryVersion:int`, `contextEpoch:int` | I11; R2; title/summary sensitive, no indexing; summary expires when supporting conversation expires |
| `conversations/{id}/messages/{id}` | `sequence:int`, `role:enum(user,assistant)`, `content:string`, `modality:enum(text,voiceTranscript)`, `state:enum(pending,completed,interrupted,failed)`, `evidenceRefs:list<EvidenceRef>`, `requestId:string`, `expiresAt:timestamp?` | I12; R2; maximum content length, no binary/audio; server decides role; only completed verified content used as history |
| `memories/{id}` | `category:enum(preference,goal,habit,routine,strategy,challenge,userFact,context)`, `statement:string`, `provenance:enum(userConfirmed,userStated)`, `status:enum(pending,active,disputed,superseded,forgotten)`, `evidenceRefs:list<EvidenceRef>`, `confirmedAt:timestamp?`, `reviewAfter:timestamp?`, `expiresAt:timestamp?`, `supersedesId:ref?`, `topicTags:list<string>` | I13; R3; inferred content cannot enter active fact memory; sensitive statements require explicit confirmation; no diagnostic categories |
| `observations/{id}` | `statement:string`, `kind:enum(aiHypothesis,deterministicPattern)`, `status:enum(candidate,active,dismissed,stale)`, `evidenceRefs:list<EvidenceRef>`, `confidence:enum(low,medium,high)`, `confidenceBasis:string`, `coverage:map`, `algorithmVersion:string?`, `modelVersion:string?`, `expiresAt:timestamp` | I14; R3; not facts; model confidence is not calibrated probability; deleted sources invalidate |
| `recommendations/{id}` | `text:string`, `basisRefs:list<EvidenceRef>`, `status:enum(proposed,accepted,dismissed,expired)`, `feedback:enum?`, `expiresAt:timestamp` | I3; R3; accepting advice is distinct from executing a mutation |
| `actionProposals/{id}` | `actionType:enum`, `validatedPayload:map`, `baseRevision:int?`, `contextEpoch:int`, `status:enum(proposed,confirmed,applied,cancelled,expired)`, `expiresAt:timestamp` | Point/I3; 24-hour maximum proposal lifetime; one-time confirmation; cannot include arbitrary URL/tool name |
| `progressSummaries/{id}` | `periodType:enum(day,week,month)`, `startDate:date`, `endDate:date`, `timeZone:string`, `metrics:map`, `coverage:map`, `algorithmVersion:string`, `sourceThroughSeq:int`, `dataEpoch:int`, `computedAt:timestamp`, `state:enum(fresh,stale)` | I15; R4; deterministic ID from period and timezone policy; AI prose kept separately |
| `reports/{id}` | `period:map`, `summaryIds:list<ref>`, `interpretation:string?`, `evidenceRefs:list<EvidenceRef>`, `status:enum`, `artifactId:ref?`, `sourceThroughSeq:int`, `dataEpoch:int` | I2; R4 for metadata, R8 for artifact; clearly label AI text and generation date |
| `artifacts/{id}` | `kind:enum(export,report,attachment)`, `objectPath:string`, `mimeType:string`, `sizeBytes:int`, `status:enum`, `expiresAt:timestamp?` | Point read; R8 for exports/reports, R1 for explicitly retained attachment; path returned only through authorized grant |

`EvidenceRef`: `entityType:enum`, `entityId:string`, `parentId:string?` for nested messages, `revision:int`, `occurredAt:timestamp?`, `fieldKeys:list<string>?`. Every reference is resolved relative to owner UID and checked for existence, revision, consent, expiry and deletion. A source reference is not proof that model prose accurately describes it; validate associated claims separately. Limit evidence lists to 20 items; retrieve extra evidence explicitly rather than unbounded arrays.

## Operational collections

| Path | Fields and role | Security / retention |
| --- | --- | --- |
| `users/{uid}/devices/{id}` | `platform`, protected `fcmToken`, `tokenUpdatedAt`, `lastSeenAt`, `notificationPermission`, `appVersion`, `localScheduleRevision` | No raw token readback; R5; token hash used for transfer cleanup across accounts |
| `users/{uid}/syncState/main` | `headSeq:int`, `minimumAvailableSeq:int`, `dataEpoch:int` | Per-user transaction serialization; R1; contention monitored |
| `users/{uid}/changes/{seq}` | `seq:int`, `entityType`, `entityId`, `revision`, `operation:enum(upsert,delete)`, `changedAt`, `expiresAt` | Metadata only, I16; R6; same-user API cursor |
| `users/{uid}/operationReceipts/{id}` | `requestHash`, `status`, `resultRefs`, `committedSeq`, `createdAt`, `expiresAt` | No full request body; point access; R6; replay with different hash fails |
| `users/{uid}/dirtyPeriods/{id}` | `period`, `requestedThroughSeq`, `dataEpoch`, `updatedAt` | R7; coalesces corrections and aggregate rebuild work |
| `users/{uid}/memorySuppressions/{id}` | `sourceEntityIds:list<ref>`, `category:enum`, `createdAt`, `expiresAt?` | No forgotten statement text; excludes re-extraction from those retained sources; remove when sources are erased or user explicitly reverses suppression |
| `users/{uid}/privacyExclusions/{id}` | `entityType?`, `entityIds?`, `dateRange?`, `scope:enum`, `createdAt`, `jobId` | Checked before reads/context/export/write; survives worker retries; removed only after erasure and resurrection protection are established |
| `users/{uid}/syncSnapshots/{id}` | `startSeq`, `pageState`, `expiresAt` | Metadata for baseline plus replay; expires after one hour; no second health-data copy |
| `users/{uid}/exportState/main` | `jobId`, `barrierExpiresAt`, `cutoffSeq`, `state:enum` | Mutation barrier with strict expiry; privacy erasure overrides; immutable export material stored privately under the job artifact and erased with it |
| `users/{uid}/aiRequests/{id}` | `conversationId`, `state`, `leaseToken`, `leaseExpiresAt`, `contextEpoch`, `modelVersion`, `usage`, `resultMessageId?`, `providerRequestId?` | R7 metadata; messages hold content; do not blindly retry ambiguous billed requests |
| `users/{uid}/voiceSessions/{id}` | `conversationId`, protected `providerCallId`, `status`, `controllerLease`, `lastHeartbeatAt`, `maxEndAt`, `reservedUsage`, `actualUsage?` | R7; provider IDs and controller tokens never exposed as authorization |
| `users/{uid}/usageBuckets/{id}` | `period`, `reservedTextTokens`, `usedTextTokens`, `reservedVoiceSeconds`, `usedVoiceSeconds`, `revision` | Server only; 90-day content-free accounting then aggregated; transactional reservations |
| `jobs/{id}` | `ownerUid`, `type`, minimal `payload`, `status`, `nextAttemptAt`, `attempt`, `leaseToken`, `leaseExpiresAt`, `expiresAt` | Backend only; I17/I18; R7; per-handler payload schema |
| `notificationDeliveries/{id}` | `ownerUid`, `notificationId`, `occurrenceKey`, `deviceId`, `channel`, `state`, `attempt`, `nextAttemptAt`, `providerMessageId?`, `expiresAt` | Backend only; I17; R5; no notification body copy |
| `privacyJobs/{id}` | `ownerUid`, `type:enum(export,eraseRange,eraseAccount)`, `state`, `cursor`, `cutoffSeq`, `createdAt`, `completedAt?`, `failureCode?` | Backend only; owner gets redacted status; R7 after completion |
| `deletionLedger/{id}` | `jobId`, keyed UID hash and key version, `scope:enum(account,records,category,dateRange)`, typed entity/parent identifiers or category/range selector, explicit range time basis and boundaries, `cutoffSeq`, deletion timestamp, backup suppression expiry, recovery-copy acknowledgement | Restricted recovery operators; no health values or free text; retain through last recoverable backup expiration, then erase |
| `securityEvents/{id}` | pseudonymous actor, action enum, outcome enum, timestamp, request ID | Restricted operators; R7 security period; never prompts, tokens or health values |

The deletion ledger covers selective erasure as well as account erasure. Selectors must identify the affected records and dependent artifacts unambiguously; large identifier sets use bounded immutable chunks with a manifest. Selective replay applies the recorded cutoff so later legitimate records are preserved; account erasure suppresses the entire account. Identifier and scope metadata remain sensitive and access-restricted.

Persist the exclusion, privacy job and ledger outbox atomically. A worker copies the immutable ledger manifest to a protected Firebase Storage recovery location outside the Firestore restore boundary, with acknowledgement recorded before erasure is reported complete. Do not return an accepted-erasure receipt until the independent manifest is durable; a timeout is retried with the same idempotency key while the local exclusion remains active. This prevents an acknowledged pending erasure from disappearing in a database rollback. The current recovery copy must survive database rollback; restoring an old in-database ledger is insufficient. Recovery stays closed if manifests or acknowledgements cannot be reconciled. Retain the HMAC key versions required to match restored owners for the suppression period.

## Query and index catalog

Default single-field indexes only where queried; exempt text, notes, arrays/maps of nutrients, content, summaries, evidence lists, tokens and raw payloads. Do not add every possible composite index. Index definitions are future implementation artifacts, not created now.

| ID | Query / proposed index |
| --- | --- |
| I1 | Per log collection: `deletedAt ASC, occurredAt DESC, __name__ DESC`; live docs explicitly store `deletedAt:null`; bounded date range |
| I2 | Per selected collection: `createdAt DESC, __name__ DESC`; savedFoods may use normalized name prefix, no full-text service initially |
| I3 | Per collection: `status ASC, updatedAt DESC, __name__ DESC` |
| I4 | goalRevisions: `goalId ASC, effectiveFrom ASC` |
| I5 | bodyMeasurements: `site ASC, occurredAt DESC` |
| I6 | Imported records: equality on `sourceGroup, sourceRecordId`; use deterministic hashed ID where possible instead of query uniqueness |
| I7 | habitLogs: `habitId ASC, localDate ASC`; ID guarantees occurrence uniqueness |
| I8 | dailyCheckIns document ID range (local date) |
| I9 | reminders: `enabled ASC, nextDueAt ASC`; scheduler primarily queries global job queue, not every user |
| I10 | notifications: `createdAt DESC, __name__ DESC`; optional unread query adds `readAt` |
| I11 | conversations: `status ASC, lastMessageAt DESC` |
| I12 | messages: `sequence ASC` within one conversation |
| I13 | memories: `status ASC, category ASC, updatedAt DESC`; bounded topic filtering after retrieval |
| I14 | observations: `status ASC, expiresAt ASC`; bounded candidate retrieval |
| I15 | progressSummaries: `periodType ASC, startDate ASC` |
| I16 | changes: `seq ASC`; cursor is a sequence, not client wall time |
| I17 | jobs/deliveries: `status ASC, nextAttemptAt ASC, __name__ ASC` |
| I18 | jobs: `status ASC, leaseExpiresAt ASC` for reclamation |

For aggregate rebuilds, query per-user source collections by localDate range with deletedAt filtering; add `deletedAt ASC, localDate ASC` indexes for affected metrics. Query shapes must be tested in a real nonproduction Firestore project because emulator behavior does not prove deployed index readiness.

## Consistency, deletion and scaling

Use transactionally enforced unique operation IDs, revision preconditions and same-user foreign-key validation. Firestore does not provide relational foreign keys. Deleting a parent must explicitly handle children; deleting a document does not recursively remove subcollections. See [Firestore deletion documentation](https://firebase.google.com/docs/firestore/manage-data/delete-data).

A source correction/deletion increments `dataEpoch` when it affects AI evidence or privacy, writes feed tombstones and schedules derived-data invalidation. Any read of memory/summary/context must verify epoch and evidence before use. Exact-match entity ID creates cannot resurrect an existing tombstone. After feed retention, operations older than 30 days are never blindly replayed.

Per-user sequence is intentionally serialized for low-volume personal tracking. Batch health imports into summaries/normalized intervals rather than thousands of raw sensor samples. Load-test one busy user and global scheduler separately. If sequence contention is measured, introduce per-domain streams with a versioned cursor; do not shard preemptively.

Store no binary media in Firestore. Storage paths are `users/{uid}/artifacts/{artifactId}/{objectName}` without names or health values. Uploads require server-created grants, object size/type limits and post-upload validation. No public buckets or permanent share tokens. Reports/exports are private and temporary. Validate content and strip image metadata if future uploads are enabled.
