# Environments, CI/CD, observability and costs

Status: proposed, 2026-09-16. No environments, workflows, secrets or cloud resources are configured in this phase.

## Environment separation

| Environment | Purpose | Data/services | Promotion boundary |
| --- | --- | --- | --- |
| Local | Developer feedback | Firebase emulators, fake AI/FCM, synthetic fixtures; optional explicit sandbox integration | No production credentials; local-only debug attestation |
| Development | Shared integration | Dedicated Firebase/Vercel/OpenAI projects; low quotas and synthetic data | Deploy trusted merged work |
| Test/SIT | Repeatable end-to-end integration | Separate real Firebase services, test devices and restricted provider budget | Automated regression and integration signoff |
| Staging/UAT | Production-like release validation | Separate projects/keys/buckets; release builds; synthetic or consented tester data | Product, security and health-safety approval |
| Production | Real users | Isolated least-privilege identities and audited changes | Protected release promotion and rollback plan |

Use distinct mobile flavors/bundle identifiers for nonproduction builds. Visible environment label on nonproduction builds prevents confusion. Keep API origin, public Firebase client config, feature flags and build metadata in typed configuration; secrets only in platform secret stores. This documentation intentionally supplies no actual values. Validate config at startup and reject mismatched project IDs/audiences.

Physical project separation is selected for all shared environments; if budget later requires consolidating dev/SIT, record an architecture decision and keep namespaces/identities separated. Never consolidate production with previews. Choose Firestore/Storage region before provisioning, considering jurisdiction, latency, provider availability and recovery requirements.

## GitHub workflow and branches

Keep `main` protected and releasable. Future work uses short-lived `codex/<topic>` or team-approved feature branches, pull requests and squash merges. Require review and successful checks; no direct production push from a developer workstation. Schema, prompt, rules and API changes receive domain-owner review. This phase does not create branches, commits or pull requests.

PR pipeline: documentation links/format → Dart/TypeScript formatting and static analysis → unit/widget/API/rules tests → emulated integration → dependency/secret/static security scans → Android build and iOS compilation on macOS. Pin action revisions and toolchains; use locked dependency installs. Generate and diff API contracts/fixtures in the future build to detect drift.

Fork/untrusted PR jobs receive no secrets and cannot execute privileged deployment scripts. Use least-privilege workflow permissions, protected environments, reviewed reusable workflows and deployment concurrency locks. Prefer short-lived OIDC credentials over durable cloud keys; see [GitHub OIDC](https://docs.github.com/en/actions/concepts/security/openid-connect).

## Promotion and release

1. Merge to main after checks; deploy API to development and run smoke tests.
2. Promote the same reviewed revision to SIT; run real-service integration, indexes/rules checks and provider-budgeted evaluations.
3. Create a release candidate; build signed Android/iOS artifacts using protected signing identities and macOS/Xcode for iOS. Distribute through internal Play testing/TestFlight after credentials are configured in a later phase.
4. Staging/UAT validates migration, privacy, safety, accessibility, performance and store disclosures. Record approvals and rollback instructions.
5. Deploy additive server/index/rules changes before mobile rollout. Wait for indexes to become ready. Keep old client contracts working; use feature flags to activate only after compatibility checks.
6. Release mobile builds in staged cohorts, monitor crash/error/cost/safety signals, pause rollout on regressions. Store review timing and policies must be checked at release.

API rollback redeploys the last compatible version; schema changes are forward-compatible and rollback tested. Mobile rollback usually means halting rollout and shipping a corrected build, not instant binary replacement. Server kill switches can disable AI/voice/imports while preserving tracking. Do not rely on an app-store update to stop uncontrolled AI spend.

Signing keys/certificates and App Store/Play credentials are stored in protected secret systems; artifacts are access-controlled. Maintain SBOM/dependency inventory and release notes. No workflow or key is created now.

## Operational telemetry

| Signal | Measurements | Data minimization |
| --- | --- | --- |
| Mobile stability | Crash-free sessions, launch latency, frozen frames, cache/sync failure class | Crashlytics scrubbed; no health breadcrumbs or prompts |
| API | Request count, latency p50/p95/p99, status class, timeouts, dependency errors | Request ID, route template and pseudonymous actor only |
| AI | Model/prompt version, input/output usage, context budget, completion latency, refusal/validation counts | No raw context, transcript or free-text reason in telemetry |
| Voice | Admission failures, setup time, disconnect class, call duration, sideband lease failures, termination lag | No audio, SDP or captions in logs |
| Jobs/notifications | Queue lag, lease expiry, attempts, unknown delivery, dead-letter counts, stale tokens | Safe template IDs and outcome enums only |
| Privacy | Export/erasure duration, stuck jobs, residual-object reconciliation | Content-free status; restricted access |
| Product outcomes | Opt-in active days, successful logging flows, reminder enablement, explicit helpfulness feedback | No metric values, exact goals or health category labels sent to Analytics |

Operational telemetry required for security/reliability is documented separately from optional product analytics. Validate SDK startup collection settings and app privacy disclosures. Centralize a redaction allowlist and test it; application exception strings may contain sensitive data even if their key looks harmless.

## Alerts and service targets

Initial alert proposals: API 5xx >2% for 10 minutes with minimum traffic; non-AI p95 >1 second for 15 minutes; job lag >5 minutes; privacy job approaching seven-day SLA; controller lease expiry/termination failures; sudden authentication denial increase; daily budget burn >80% expected pace. Tune using staging/early-production baselines to avoid alert fatigue.

Assign an on-call owner and runbooks for auth outage, Firestore errors, bad rules deployment, AI timeout/spend spike, stuck deletion, lost controller and push backlog. User-facing status must not disclose health information. Track meaningful aggregate success such as reliable saved entries and explicit usefulness, not only chat duration.

Targets: 99.9% monthly ordinary API availability, RPO 24 hours, RTO 8 hours, and the latency targets in [requirements](PRODUCT_REQUIREMENTS.md). These are aspirations until measured and funded. AI and push depend on external services; publish separate availability/failure treatment rather than implying guaranteed delivery.

## Recovery and migrations

Configure backups/PITR with reviewed retention and access; test restore into an isolated project. Reconcile and apply the current immutable deletion manifests from the protected Firebase Storage recovery location, which must not be overwritten or rolled back with Firestore. Replay account and selective scopes with their cutoffs before allowing restored data to serve users, rebuild derived summaries and reconcile outstanding jobs/tokens. Missing manifests, unresolved journal gaps or unavailable matching-key versions block reopening. Backups without a tested restore do not satisfy recovery. Keep restore credentials separate from ordinary API credentials and retain recovery metadata through the last recoverable backup expiry.

Run versioned idempotent data migrations with dry-run counts, bounded batches, checkpoints and post-checks. Deploy expand → migrate → contract; retain compatibility while older mobile versions remain supported. Purge unused indexes only after query telemetry confirms safety. Export fixtures help future Firestore migration; avoid provider-specific values in portable domain formats.

## Cost model and controls

Do not quote unverified current prices. Before provisioning, populate a budget worksheet from live official pricing and approved usage assumptions. Monthly estimate:

`AI text = turns × (average uncached input tokens × input rate + cached tokens × cached rate + output tokens × output rate)`

`Voice = measured input/output audio and text usage × corresponding model rates + controller runtime/egress`

`Data/backend = Firestore reads/writes/deletes/index storage/backups + Storage bytes/operations/egress + Vercel invocations/CPU/memory/network + scheduled work + build/signing/test infrastructure`

Rates must use consistent units (for example per million tokens); voice minutes are a product quota, not a substitute for token-based billing. FCM delivery may have no direct per-message fee under current offerings, but scheduling, database and backend operations still cost money; verify pricing at launch rather than budget push as entirely free infrastructure.

| Cost driver | Design control | Expansion trigger |
| --- | --- | --- |
| Text inference | Bounded 10k input/1.5k output policy, per-user reservations, one active turn, caching and reviewed model routing | Increase only after quality/latency evaluation and budget approval |
| Voice | One active session, 10-minute cap, idle timeout, daily allowance, server hangup and watchdog | Increase after measured per-session cost and failure allowance |
| Context/history | Relevant summary/memory retrieval, at most 20 raw evidence records, capped tool rounds | Add retrieval infrastructure only if measured recall fails |
| Firestore | Cached mobile reads, paginated API, precomputed summaries, no unbounded listeners/scans, coalesced dirty periods | Inspect read/write amplification per user before scaling |
| Storage | No raw audio, temporary reports/exports, upload size caps and cleanup | New media feature requires a storage/privacy budget |
| Jobs/notifications | Indexed due queries, bounded batches, leases, retry deadlines and local reminders | Move work execution to durable queue/runtime only when measured lag requires it |
| Backend/controller | Co-location, bounded request deadlines, reused SDK clients, controller scale limits | Load tests determine concurrency and min-instance tradeoff |
| Observability | Allowlisted metrics, sampled nonsecurity traces, retention caps | Add detail only for demonstrated operational need |

Budgets require persistent server enforcement; vendor alerts are not always hard stops. Reserve worst-case usage transactionally and refund unused capacity from measured outcomes. Maintain environment and project-wide kill switches in addition to per-user limits. When quota service is unavailable, fail closed for new AI calls while keeping local tracking available. Free tier is not a production capacity assumption.

Review spend by active user, text turn, voice session and daily sync. Initial load model to measure in P1/P10: 1,000 daily active users, 20 tracking mutations and 10 text turns per active user/day, 10% using 10 voice minutes/day. These are sizing scenarios, not forecasts; product owner must replace them with approved projections and a spending ceiling.
