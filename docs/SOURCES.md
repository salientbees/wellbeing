# Official sources and evidence register

Documentation reviewed on **2026-09-16**. These are links actually opened during architecture research. Provider pages are live and may change; repeat verification at each integration/release gate. Package pages below are publisher/maintainer sources, not a claim that every dependency is maintained by Flutter or OpenAI.

All uncited policy numbers in the blueprint are project proposals. This register does not establish account entitlements, pricing, contractual retention, medical effectiveness or legal compliance. No authenticated cloud resources were inspected or created.

## OpenAI

| Source | Decision informed |
| --- | --- |
| [Realtime API overview](https://developers.openai.com/api/docs/guides/realtime) | Realtime architecture and current documented model example; do not mix it with GPT-Live schemas |
| [WebRTC](https://developers.openai.com/api/docs/guides/voice-webrtc) | Server-brokered SDP/call creation and alternative ephemeral credentials |
| [Server-side controls](https://developers.openai.com/api/docs/guides/voice-server-controls) | Server sideband for control and private tool execution |
| [Realtime conversations](https://developers.openai.com/api/docs/guides/realtime-conversations) | Turn events, cancellation/interruption and history alignment |
| [Realtime call hangup](https://developers.openai.com/api/reference/resources/realtime/subresources/calls/methods/hangup) | Server termination operation; actual failure/retry behavior must be exercised in P8 |
| [Structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs) | Typed AI payloads; application still validates evidence/safety |
| [Data controls](https://developers.openai.com/api/docs/guides/your-data) | Endpoint retention, stored state and limits of store:false |

The older guessed `realtime-webrtc` and `realtime-server-controls` URLs returned 404 during research. The linked `voice-webrtc` and `voice-server-controls` pages were reached through the official documentation navigation and used instead. Do not implement against an old tutorial without checking current API reference and selected-model events.

## Flutter, Dart and maintained packages

| Source | Decision informed |
| --- | --- |
| [Flutter architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations) | UI/data separation, repositories, DI and testability |
| [Flutter accessibility](https://docs.flutter.dev/ui/accessibility) | Semantics, accessible interaction and testing |
| [Riverpod getting started](https://riverpod.dev/docs/introduction/getting_started) | Stable provider-based state/DI; experimental features excluded |
| [go_router](https://pub.dev/packages/go_router) | Declarative routing and guarded deep links |
| [Dio](https://pub.dev/packages/dio) | HTTP cancellation, interceptors and deadlines |
| [Freezed](https://pub.dev/packages/freezed) | Immutable state/DTO variants |
| [json_serializable](https://pub.dev/packages/json_serializable) | Typed serialization |
| [Drift](https://pub.dev/packages/drift) | Local relational cache and transactions; encryption is a separate requirement |
| [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | Platform secure storage and key-lifecycle considerations |
| [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) | Native notification integration and platform caveats |
| [timezone](https://pub.dev/packages/timezone) | IANA timezone calculations |
| [flutter_webrtc](https://pub.dev/packages/flutter_webrtc) | Candidate native WebRTC adapter, subject to device spike |

Versions shown on package pages are not blindly copied into future manifests. P1 pins a tested compatible stable set; no dependencies were installed for this task.

## Firebase

| Source | Decision informed |
| --- | --- |
| [Flutter setup](https://firebase.google.com/docs/flutter/setup) | Official FlutterFire integration |
| [Verify ID tokens](https://firebase.google.com/docs/auth/admin/verify-id-tokens) | Backend token verification and revocation distinction |
| [App Check custom backend](https://firebase.google.com/docs/app-check/custom-resource-backend) | Attestation verification in Vercel/controller |
| [Firestore conditions](https://firebase.google.com/docs/firestore/security/rules-conditions) | Rules boundary and Admin bypass |
| [Offline data](https://firebase.google.com/docs/firestore/manage-data/enable-offline) | Offline SDK tradeoff; API/outbox chosen instead |
| [Transactions and batches](https://firebase.google.com/docs/firestore/manage-data/transactions) | Atomic mutation metadata and retry-safe transactions |
| [Write-time aggregation](https://firebase.google.com/docs/firestore/solutions/aggregation) | Precomputed metrics; application-owned job mechanism |
| [Delete data](https://firebase.google.com/docs/firestore/manage-data/delete-data) | Explicit recursive cleanup of subcollections |
| [Storage security](https://firebase.google.com/docs/storage/security) | Private files and separation of rules from signed grants |
| [FCM token management](https://firebase.google.com/docs/cloud-messaging/manage-tokens) | Token refresh, stale/invalid cleanup and device lifecycle |

## Hosting, identity and CI/CD

| Source | Decision informed |
| --- | --- |
| [Vercel function limits](https://vercel.com/docs/functions/limitations) | Bounded work and runtime constraints |
| [Vercel WebSockets](https://vercel.com/docs/functions/websockets) | Current beta support; avoid outdated unsupported claims |
| [Vercel Cron management](https://vercel.com/docs/cron-jobs/manage-cron-jobs) | No automatic invocation retry; durable application job state |
| [Vercel to GCP federation](https://vercel.com/docs/oidc/gcp) | Short-lived cloud identity instead of broad static credentials |
| [Cloud Run WebSockets](https://docs.cloud.google.com/run/docs/triggering/websockets) | Narrow long-lived voice runtime with timeout/reconnect handling |
| [GitHub Actions OIDC](https://docs.github.com/en/actions/concepts/security/openid-connect) | Federated deployment identity |

## Platform health and safety context

| Source | Decision informed |
| --- | --- |
| [Apple HealthKit](https://developer.apple.com/documentation/healthkit) | Native health-integration boundary; page body extraction was limited, so detailed entitlements/permissions remain a P9 verification gate |
| [Android Health Connect](https://developer.android.com/health-and-fitness/health-connect) | Android health import boundary and opt-in integration planning |
| [WHO mental health](https://www.who.int/health-topics/mental-health) | General support/professional-care context; not product clinical validation |

## Explicit verification gates

Before implementation of each provider integration, re-open its API reference for exact request/event schemas, supported SDK versions and regional availability. Before provisioning, check current pricing/plans, identity federation support, region choices and backup controls. Before store submission, check current Apple/Google privacy, health-data, sign-in and billing policies for the chosen product model. Those account- and market-specific checks are deliberately not represented as completed by this architecture research.
