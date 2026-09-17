# Flutter application architecture

Status: proposed, 2026-09-16. Covers presentation, state, platform integration and offline behavior. No Flutter project or generated files exist yet.

## Layers and feature structure

Use feature-oriented modules: auth, onboarding, profile, goals, weight, measurements, nutrition, hydration, activity, workouts, sleep, mood, habits, checkIn, dashboard, calendar, reminders, notifications, coach, memory, progress, reports, settings and privacy. Shared capabilities live in core only when used by multiple features; avoid a large miscellaneous utility layer.

Within a feature, `presentation/` contains screens/widgets, `application/` contains controllers/use cases, `domain/` contains entities and repository ports, and `data/` contains DTOs, mappers and repository implementations. Simple read-only features may omit a redundant use-case layer; important domain policies remain pure Dart. Widgets never call Firebase Admin, HTTP endpoints or SQL directly. Domain types do not expose Firestore snapshots, provider JSON or framework BuildContext.

Proposed core modules: `core/api`, `core/auth`, `core/sync`, `core/storage`, `core/clock`, `core/units`, `core/errors`, `core/accessibility`, `core/notifications`, `core/telemetry` and `core/design`. Inject Clock, ID generator, API client, local store, authenticated principal and platform capability ports so tests can replace them.

This is consistent with [Flutter's separation and repository recommendations](https://docs.flutter.dev/app-architecture/recommendations); exact folder names and Riverpod are project choices.

## State management and dependencies

| Dependency | Role and reason | Guardrail |
| --- | --- | --- |
| flutter_riverpod | Provider-based DI; Notifier/AsyncNotifier for explicit states and async lifetime | Use stable APIs; do not rely on experimental offline persistence/mutations |
| go_router | Tab shell, deep links, auth/onboarding guards, route restoration | Validate notification links against an allowlist and ownership after authentication |
| Freezed + json_serializable | Immutable DTOs and sealed result/state variants, consistent wire serialization | Generate only in implementation; keep domain separate from wire defaults |
| Dio | API transport, cancellation, auth refresh, request deadlines | No automatic POST retry unless idempotency rules permit it; never log bodies/headers |
| Drift/SQLite | Transactional cache, outbox, migrations and query streams | Encryption requires an independently validated integration; Drift itself is not encryption |
| flutter_secure_storage | Protect local encryption keys and small app secrets | Respect platform backup/key lifecycle; not for large health payloads |
| FlutterFire Auth / App Check | Identity and app attestation | Per-environment initialization; no server credentials in app |
| FlutterFire Messaging | Token lifecycle and push receipt | Permission denial is supported; payloads contain no health values |
| FlutterFire Analytics / Crashlytics | Optional product analytics and scrubbed crash diagnostics | Collection off until configured consent policy permits it |
| flutter_local_notifications + timezone | OS reminders and IANA wall-clock handling | Validate OS scheduling limits, DST and permission behavior |
| flutter_webrtc | Native WebRTC media abstraction | Community-maintained adapter, not an official OpenAI Dart SDK; validate real devices |
| Flutter localization tooling / intl | Externalized strings, pluralization, units/dates and RTL readiness | No English text baked into domain logic |

Maintainer sources: [Riverpod](https://riverpod.dev/docs/introduction/getting_started), [go_router](https://pub.dev/packages/go_router), [Freezed](https://pub.dev/packages/freezed), [json_serializable](https://pub.dev/packages/json_serializable), [Dio](https://pub.dev/packages/dio), [Drift](https://pub.dev/packages/drift), [secure storage](https://pub.dev/packages/flutter_secure_storage), [FlutterFire](https://firebase.google.com/docs/flutter/setup), [local notifications](https://pub.dev/packages/flutter_local_notifications), [timezone](https://pub.dev/packages/timezone), [WebRTC](https://pub.dev/packages/flutter_webrtc).

At P1 choose a compatible stable Flutter/Dart toolchain and pin package versions. Review licenses, maintenance and supported OS requirements. Avoid extra DI frameworks, parallel HTTP clients and a second state management library. For health imports, define a native interface first, then assess a maintained plugin or small platform-channel implementation against [HealthKit](https://developer.apple.com/documentation/healthkit) and [Health Connect](https://developer.android.com/health-and-fitness/health-connect).

## Repository behavior

Each repository offers domain reads as cached streams and explicit commands returning typed results. Local save writes a projection and outbox entry in one transaction before reporting success. UI labels distinguish `savedOnDevice`, `syncing`, `synced`, `conflict` and `failed`; "saved" must not imply cloud persistence. Online-only commands (AI, export, account deletion) are visibly separate and cannot be silently queued.

An account-scoped SyncCoordinator drains outbox in stable per-entity order. Operations retain ID, base revision, creation time, retry count and next attempt. Retry transient network failures with jitter; stop for validation/consent/auth conflicts. Connectivity signals are hints: actual request outcomes determine success. Foreground resume triggers sync; OS background execution is best effort, never a promise.

The client downloads the change feed after upload and installs pages transactionally with cursors. Full resync uses baseline enumeration plus change replay, preserving pending drafts separately. An expired operation window prompts reconciliation, not resurrection of a deleted record. On conflict display local and confirmed server values with times and let the user choose. Units are normalized before comparison.

Cache a configurable recent window (initially 90 days of tracking, 30 days of conversation display, active plans and summaries), with paginated on-demand history. Local retention never exceeds server privacy policy intentionally; reconcile remote deletions at next connection. Keep keys and databases separated per UID. Sensitive in-memory providers are disposed on account change.

## Forms and screen states

Every data screen defines initial loading, refreshing-with-existing-data, empty, partial, offline/stale, error, pending mutation and conflict states. Empty copy invites logging without fabricating chart points. Use skeletons only when useful and preserve focus/drafts across transient network failure.

Validate required fields, finite numbers, unit conversions, date order, portion sizes and engineering bounds on device; server revalidates. Use locale-aware entry and normalize decimal separators. Show unusually large changes for confirmation without describing them as medically safe. Do not use input validation to prescribe target weight, water or energy intake.

Undo uses a new revisioned command; it does not rewind a client cache while leaving server state changed. Destructive account actions require explicit UI confirmation and recent reauthentication. Long reports/exports show job state and remain cancellable where feasible.

## Navigation and design system

go_router shell preserves tab state for Home, Track, Coach, Progress and Plan. Guard sign-in, account status and incomplete mandatory onboarding. A deep link carries opaque entity ID only; the target loads through owner-scoped API. Resume the intended route after successful auth, but never display another account's cached screen.

Design tokens cover typography, spacing, surfaces, contrast, focus, motion and semantic status. Use Material 3 with native back behavior, safe areas and platform-appropriate controls. Mood/goal colors have accompanying labels/icons. Charts include accessible summaries and tables; avoid meaning that depends on color alone. Support light/dark themes and reduced motion without changing data semantics.

Localize all user-visible strings, safety copy, notification templates and units. Safety translations require review rather than runtime unconstrained AI translation. Test long strings, RTL layout and culturally appropriate date/week boundaries. Do not infer country or health advice from language alone.

## Accessibility and platform capabilities

Follow [Flutter accessibility guidance](https://docs.flutter.dev/ui/accessibility). Provide meaningful semantic labels, logical focus order, touch targets, switch/keyboard access where supported, 200% text scaling and non-color chart summaries. Voice has captions, mute/end labels and a complete text alternative. No feature requires speech or audio perception.

Platform ports isolate microphone permissions, audio focus, secure storage, local notifications, health imports, app lifecycle and share/download handling. iOS signing/build validation needs macOS/Xcode; this Windows workspace cannot validate iOS release binaries alone. P1 must establish a macOS runner and physical iPhone access before promising iOS readiness.

## Failure handling and validation

Map transport/provider details to domain failures: unauthenticated, forbidden, validation, conflict, offline, rateLimited, unavailable and unknown. Show a safe message and request ID; never provider stack traces. Auth refresh is single-flight to avoid token-refresh storms. All retries have a bound and cancellation path.

Unit tests cover repositories/controllers with provider overrides and fake clock. Widget tests cover states, forms and semantics. Integration tests exercise durable outbox after process death, two devices editing one record, account switching, permission denial and deep links. Physical-device tests cover backgrounding, notifications, microphone/Bluetooth, VoiceOver/TalkBack and encrypted storage artifacts. See [test strategy](TEST_STRATEGY.md).
