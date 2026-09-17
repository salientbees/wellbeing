# Wellbeing

Architecture and implementation blueprint for a personal wellbeing application for Android and iOS, with text and voice coaching.

**Status: local implementation in progress; not production-ready.** Flutter authentication/onboarding, encrypted offline tracking, dashboard/progress, account preferences/consents, backend synchronization, and tested AI context/provider foundations are implemented. No cloud services are provisioned or deployed. See [local setup, validation and known gates](docs/LOCAL_DEVELOPMENT.md).


## Executive architecture

Use Flutter/Dart for the mobile application, Firebase Authentication for identity, Firestore for authoritative data, Firebase Storage for private artifacts, and FCM for push. A modular TypeScript backend on Vercel owns all application data access, validation, deterministic calculations, and OpenAI text orchestration. An encrypted local store and durable outbox support offline tracking. Direct client Firestore access is denied by design.

The coach receives a bounded, evidence-linked context assembled by the backend. User statements, measured records, deterministic patterns, and AI observations have distinct provenance. Memory is visible, correctable, revocable, and never silently promoted from inference to fact.

Production realtime voice uses OpenAI WebRTC media with server-controlled session establishment and tools. A narrowly scoped Google Cloud Run voice controller is the proposed exception to Vercel-only execution: it owns a long-lived control connection. It shares domain modules with the API and introduces no separate business-data store. This decision must be re-evaluated at the voice implementation gate; Vercel currently labels its WebSocket support beta.

## Read the blueprint

| Document | Responsibility |
| --- | --- |
| [Product requirements](docs/PRODUCT_REQUIREMENTS.md) | Scope, all 32 modules, UX, assumptions and measurable outcomes |
| [System architecture](docs/ARCHITECTURE.md) | Stack, boundaries, flows, backend and architectural decisions |
| [Database schema](docs/DATABASE_SCHEMA.md) | Canonical names, types, indexes, ownership and retention |
| [API specification](docs/API_SPECIFICATION.md) | Contracts, authorization, synchronization, errors and idempotency |
| [Flutter architecture](docs/FLUTTER_ARCHITECTURE.md) | Layers, dependencies, state, offline storage and accessibility |
| [AI architecture](docs/AI_ARCHITECTURE.md) | Grounding, context, memory, safety and evaluations |
| [Voice architecture](docs/VOICE_ARCHITECTURE.md) | Authentication, media, controls, lifecycle and failure recovery |
| [Security model](docs/SECURITY_MODEL.md) | Threat model, isolation, secrets, consent, export and erasure |
| [Notification architecture](docs/NOTIFICATION_ARCHITECTURE.md) | Local/push ownership, scheduling, quiet hours and retries |
| [Analytics and insights](docs/ANALYTICS_AND_INSIGHTS.md) | Deterministic formulas, quality, patterns and reports |
| [Test strategy](docs/TEST_STRATEGY.md) | Automated/manual coverage and release gates |
| [Operations and delivery](docs/OPERATIONS_AND_DELIVERY.md) | Environments, CI/CD, observability, recovery and costs |
| [Development plan](docs/DEVELOPMENT_PLAN.md) | Phases, expected modules, tests, acceptance and checkpoints |
| [Architecture review](docs/ARCHITECTURAL_REVIEW.md) | Risks, mitigations and unresolved launch decisions |
| [Official sources](docs/SOURCES.md) | Documentation consulted and decision links |

## Reading conventions

All paths describing future source files are proposed, not existing files. Numeric limits are initial engineering policy proposals unless explicitly identified as provider limits. SDK versions, billing plans, regions, medical-safety copy and launch jurisdictions must be validated at their roadmap gates. This blueprint does not claim clinical validation or regulatory certification.

The schema is authoritative for persisted field names; the API specification is authoritative for wire behavior; the security model controls authorization and retention interpretation. Changes spanning them must update all affected documents in one future pull request.

## Implementation status

Implementation follows the approved development plan. Use the local setup guide to run Firebase emulators, the API and Flutter. Git milestones capture validated progress, not production release approval. Erasure/export, notification delivery, live AI/voice, imports, localization and release hardening remain outstanding.
