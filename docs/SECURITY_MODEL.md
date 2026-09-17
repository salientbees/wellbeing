# Security, privacy and health-data controls

Status: proposed, 2026-09-16. No secrets or configuration values are included. This design is not a compliance certification; jurisdiction-specific obligations require review before launch.

## Threat model and trust boundaries

Protect wellbeing records, conversations, identity links, memory, private artifacts and provider spending against cross-account access, stolen sessions, malicious clients, prompt injection, accidental telemetry exposure, leaked credentials and incomplete deletion. Treat mobile requests, imported records, FCM tokens, model output and third-party callbacks as untrusted.

Backend services have privileged database access; an authorization defect there is a primary risk. Device attestation, TLS, Firestore rules and prompt instructions are separate controls and do not replace application authorization.

## Authentication and authorization

Use Firebase Authentication SDK on mobile. Require verified email for email/password accounts before cloud data/AI access; provider sign-ins use their verified identity claims under tested policy. Support password reset, reauthentication, safe account linking and explicit logout. Never merge accounts solely because an unverified email matches. Authentication error UI avoids account enumeration.

On each API admission verify ID token signature, expiry, issuer, audience and project through Firebase Admin. Check revocation/disabled status for sensitive actions and a bounded cached active-account status for ordinary requests; proposed cache maximum 60 seconds. Deletion/consent invalidation additionally uses live lifecycle/epoch checks for AI and mutations. [Firebase ID-token verification](https://firebase.google.com/docs/auth/admin/verify-id-tokens) distinguishes verification from revocation checking; configure both deliberately.

Build a principal from verified UID. Repositories require that principal and construct `users/{uid}` paths internally. Request body UID/path/role fields are rejected. Nested ownership checks cover conversations/messages, evidence, goals, schedules, files, devices and voice calls. Return 404 for another user's object, without exposing existence. Internal scheduler identity cannot be supplied through a user endpoint.

Recent Firebase `auth_time` within five minutes is required for exports, account deletion and destructive bulk erasure. Single-record edits/deletion use normal authenticated revision checks. Support optional biometric app unlock as device privacy, never as a substitute for server authentication.

## Firestore, Storage and IAM

Client Firestore rules deny all reads/writes to all collections. Application access goes through the Vercel API. Client Storage rules also deny direct access initially; backend issues narrowly scoped, short-lived grants after ownership checks. There are no public user collections, wildcard authenticated-user rules or client-writable AI memories/usage counters.

Firebase Admin bypasses Firestore Security Rules. Use least-privilege service accounts, separate environments, scoped backend methods and mandatory two-user negative API tests. IAM is not a per-document tenant filter. [Firestore rules guidance](https://firebase.google.com/docs/firestore/security/rules-conditions) is the reference for that boundary; [Storage rules](https://firebase.google.com/docs/storage/security) cover client SDK access, while signed grants require separate server enforcement.

No permanent Firebase download-token URLs for sensitive artifacts. A download grant is a bearer capability: limit to one object, short expiry (proposed five minutes), no list/write permission, and don't log it. For immediate revocation needs, proxy download through the authenticated backend; already issued signed URLs may remain usable until expiry or object removal. Uploads require exact object key, declared size/type, actual-content verification and metadata stripping. Disable arbitrary URL imports to avoid SSRF.

## Secrets and environment isolation

OpenAI keys, signing material, internal scheduler credentials and platform service credentials remain server-side. Firebase public client configuration is not an authorization secret, but no real configuration values are created in this phase. Never place server keys in Dart defines, mobile assets, source, logs or CI artifacts.

Prefer workload identity federation for Vercel-to-Google Cloud and GitHub deployments, with issuer/audience/repository/environment constraints. [Vercel GCP federation](https://vercel.com/docs/oidc/gcp) documents the integration. If a required runtime cannot use federation, use a dedicated rotated secret credential with minimal role, explicit owner and audit; no shared administrator key. Cloud Run uses its service identity. OpenAI project keys are separate per environment and rotated on exposure.

Production identities, Firebase projects, Storage buckets, OpenAI projects and deployment permissions are separate from development/test/staging. Never test with production exports. Preview deployments receive no production credentials. Configuration validation rejects environment/project mismatches at startup.

## API validation and abuse prevention

Use runtime schemas, strict unknown-field rejection, field and array bounds, normalized units, revision preconditions and request size/deadline limits. App Check is required on production supported clients, with a staged rollout and monitored false rejection rate. Verify tokens on the custom backend as documented by [Firebase App Check](https://firebase.google.com/docs/app-check/custom-resource-backend). Debug tokens are local/test only.

Persistent per-user rate/budget limits plus coarse edge/IP controls prevent simple replay/spend abuse. In-process counters do not work across serverless instances. Reserve cost before provider calls. Reject arbitrary model IDs, context messages with privileged roles and tool definitions. Authenticate cron requests and provider callbacks; deduplicate job and event IDs. CORS is browser policy, not authorization for a native app.

Render AI text as safe text/limited Markdown with no raw HTML, auto-navigation or executable links. Allowlist internal navigation targets and require confirmation for external links. Treat retrieved notes and transcripts as data even when they contain instructions to reveal secrets.

## Device privacy and encryption

TLS protects transport and managed services provide configured encryption at rest; this is not end-to-end encryption because the backend and selected AI processor must access authorized plaintext. Do not claim the server cannot read user data.

Use encrypted local data storage with a per-account key held through platform secure storage (Keychain/Android-backed facilities), plus OS file protection and backup exclusion. SQLite/Drift alone does not provide database encryption. P1 must prove a maintained encrypted SQLite integration or authenticated field/payload encryption with no plaintext WAL/temp backups. Do not ship plaintext health caching while calling it encrypted.

On logout/account switch, revoke the device token association, cancel local notifications, stop voice, dispose account-scoped state, wipe cache/outbox and destroy its encryption key. Warn before intentionally discarding unsynced drafts. A lost/offline device cannot be remotely guaranteed to erase immediately; document this residual risk. Authentication tokens remain in SDK-managed secure mechanisms, never manual preferences. Hide sensitive app-switcher snapshots where supported; app lock is optional. Rooted-device compromise is outside a guarantee of secrecy.

## Consent, minimization and telemetry

Separate essential account processing from optional AI processing, persistent AI memory, health imports, product analytics and optional crash diagnostics. OS notification/microphone permission is distinct from data-processing consent. Revocation takes effect immediately for new requests, and actively terminates voice where possible. Users can continue ordinary tracking without AI or analytics.

Collect only needed fields; don't require date of birth, address, sex, diagnoses or contact lists for ordinary tracking. Store timestamps and coarse timezone, not GPS. Request only health-import types the user enables; manual tracking works after denial. Do not send health records to Firebase Analytics.

Allowlist telemetry fields. Exclude prompts, replies, audio, notes, measurements, food names, email, authorization headers, SDP, FCM tokens and signed URLs. Use pseudonymous rotating identifiers for operations, short retention and restricted dashboards. Scrub crash breadcrumbs and exception messages before emission. Analytics and crash consent are implemented before SDK collection is enabled, including default behavior during first launch. See [operations](OPERATIONS_AND_DELIVERY.md).

## Record, memory and account deletion

1. Authenticate and validate scope. In a transaction mark scope excluded, increment `dataEpoch`, create privacy job and tombstone/feed metadata. New context, exports and reads filter the excluded scope immediately.
2. Invalidate caches, queued jobs, aggregates, reports, memory and observations referencing affected evidence. Stop active voice on account/AI consent deletion. In-flight AI checks epoch before publication; late completions cannot recreate deleted content.
3. Worker deletes raw records, conversation subcollections, attachments, artifacts, candidate memories and derived content in bounded resumable batches. Keep minimal deletion metadata for sync/backups, not copied health text.
4. Forget-memory requests also install source-scoped extraction suppression markers. Deleting a source removes dependent memory unless a separately retained user-confirmation record supports it and the requested scope permits retention; explain this distinction in controls.
5. Account erasure disables writes and sign-in, revokes refresh tokens, removes devices and notifications, walks all user subcollections plus global ownerUid collections and Storage objects, and finally deletes Auth identity. Keep only restricted content-free completion/backup-suppression evidence for the approved period.
6. Reconcile until no live records remain and the scoped deletion-ledger manifest has been durably acknowledged in the independent recovery location, then mark completion. Keep logical exclusions active while pending and retry safely after worker crashes. Never assume deleting the root user document removes its subcollections.

Target active-store erasure within seven days, with immediate logical exclusion. Configure backup/PITR retention to meet the proposed 35-day maximum, record actual provider capabilities, and do not promise this before configuration verification. Restoration must apply the current independently retained deletion ledger, including record/category/date-range selectors and cutoffs defined in the schema, before any restored dataset is exposed. Remove dependent derived content as well as selected sources; preserve unrelated and legitimately later records. Fail closed if recovery journal completeness cannot be established. Firestore TTL is cleanup assistance, not an immediate erasure guarantee.

Provider-side retention is separate. `store:false` avoids intentional stored Responses state, but provider abuse-monitoring retention may remain. Review [OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data) and any available contractual controls; disclose applicable retention. Do not claim Wellbeing can delete already processed/transmitted audio instantly or control a user's downloaded files.

## Export workflow

Recent reauthentication starts an owner-scoped durable export. Export JSON/CSV with schema version, UTC/local timestamps, canonical units, provenance, coverage and a manifest; memory and observations appear in separate sections. Never include secrets, private service IDs or other users' records.

For consistent exports, establish a short per-user export snapshot barrier: queue incoming mutations without acknowledging them as committed, wait for already accepted mutations to settle, materialize the bounded data into an immutable export snapshot, then release the barrier before expensive formatting. Set a short maximum barrier duration and fail/retry the export if exceeded; large accounts require a reviewed snapshot/versioning strategy before raising limits. Privacy erasure cancels any export and overrides the barrier. Do not call an inconsistent multi-page scan a point-in-time export.

Deliver a temporary private artifact, expire after 24 hours and audit only content-free job metadata. Reports intended for sharing warn the user that they contain personal information at the explicit share action, without adding friction to ordinary viewing.

## Security release gates

All cross-user API and rules tests pass; no unresolved critical/high exploitable findings; keys absent from mobile/repository/build artifacts; successful deletion/export/restore drills; prompt injection and tool authorization tests; production logging redaction verified; threat model reviewed after each new integration. Health-safety behavior is separately reviewed and evaluated; access-control success does not establish medical safety.
