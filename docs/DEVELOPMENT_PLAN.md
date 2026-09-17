# Implementation roadmap

Status: proposed, 2026-09-16. This phase created documentation only. Begin implementation only after the user's review. Every path below is an expected future module, not a file created now.

## Delivery model

Use vertical slices with security, privacy, accessibility and tests included from the first slice. Do not postpone account deletion or ownership checks until the end. Internal pilots may ship limited functionality, but the complete production objective includes all FR-01 through FR-32, text/voice, both mobile platforms and operational readiness.

No calendar estimates are asserted without team size, budget, device access and launch-market decisions. Sequence and dependencies below are the committed blueprint proposal. Each phase exits with reviewable evidence, not only code completion.

## P0 — Architecture and product decisions

- Objective: approve this blueprint and resolve foundational assumptions.
- Components: launch geography/age scope, retention/residency, budget, OS support, accessibility cohort, legal/store disclosures and health-safety review ownership.
- Expected files/modules: updates to these documents; future architecture decision records only if needed.
- Dependencies: product owner and qualified privacy/health-safety reviewers.
- Tests: document consistency, requirement coverage and threat-model walkthrough.
- Acceptance: signed-off decisions, explicit release scope, spending ceiling and owners for open gates.
- Risks: unclear age/jurisdiction or unsupported claims create expensive redesign.
- Validation checkpoint: review [architectural risks](ARCHITECTURAL_REVIEW.md); authorize P1 separately after architecture review.

## P1 — Toolchain, contracts and feasibility

- Objective: establish reproducible foundations and prove high-risk platform choices before broad implementation.
- Components: stable Flutter/Dart and Node toolchains; repository layout; typed API schemas; emulator setup; mobile design tokens; encrypted local storage spike; iOS/macOS build access; authentication/federation feasibility; voice SDP/control spike using synthetic data only.
- Expected files/modules: future `apps/mobile`, `services/api`, `packages/backend-domain`, `contracts`, `firebase`, `.github/workflows`; encryption and voice spike tests isolated from production features.
- Dependencies: P0 decisions and explicit authorization to provision/install in a subsequent task; macOS runner and physical Android/iPhone access.
- Tests: encrypted database/WAL/backup inspection, local save/reopen, contract serialization, denied client rules, skeleton Android/iOS builds, provider sideband/SDP compatibility.
- Acceptance: pinned compatible dependencies, reproducible builds, no plaintext health persistence, provider integration assumptions demonstrated, CI with no production credentials.
- Risks: WebRTC compatibility, secure storage restoration, platform signing access and mutable provider APIs.
- Validation checkpoint: accept/revise ADR-05 and ADR-09; unresolved feasibility blocks dependent phases rather than becoming hidden technical debt.

## P2 — Identity, onboarding, profile and privacy foundation

- Objective: create a secure account boundary before personal data features.
- Components: Firebase Auth flows, onboarding/eligibility, profile/settings, consent, scoped repositories, App Check rollout, lifecycle/deletion/export job skeleton.
- Expected files/modules: `features/auth`, `onboarding`, `profile`, `settings`, `privacy`; backend `identity`, `consent`, `privacy`; rules and principal fixtures.
- Dependencies: P1; approved privacy policy and authentication-provider choices.
- Tests: token expiry/revocation/wrong project, account linking, two-user isolation, deny-all client access, logout/account switch, reauthentication and empty-account deletion.
- Acceptance: no cross-user access; optional AI/analytics consent can be denied; local state cleared on account switch; identity export/deletion succeeds.
- Risks: identity linking errors, accidental telemetry before consent and weak Admin authorization.
- Validation checkpoint: security reviewer signs off identity boundaries and every new backend route pattern.

## P3 — Offline tracking core and goals

- Objective: deliver durable daily use without AI.
- Components: local encrypted cache/outbox, sync feed/snapshot/revisions, weight, body measurements, hydration, goals/milestones and Home quick actions.
- Expected files/modules: `core/storage`, `core/sync`, `core/units`; tracking feature modules; backend mutations/feed/receipts/dirty periods; deterministic fixtures.
- Dependencies: P2; validated encryption and conflict model.
- Tests: process death, airplane mode, acknowledgment loss/retry, bulk partial success, two-device conflict, >30-day replay, deletion tombstones, unit conversion and snapshot convergence.
- Acceptance: acknowledged local data survives restart; no duplicate server writes; conflicts visible; pending vs synced labels accurate; all new collections exported/erased.
- Risks: sync complexity, deletion resurrection, excessive per-user sequence contention.
- Validation checkpoint: real two-device demo and measured outbox drain; inspect storage for plaintext after crash.

## P4 — Complete manual tracking and planning

- Objective: cover food, activity, workouts, sleep, mood, habits, check-in and calendar.
- Components: typed logs, saved foods, nutrient provenance, intervals/overlap handling, habit/schedule revisions, recurrence and linked check-in data.
- Expected files/modules: corresponding mobile features and backend modules; domain schema/validation, schedule and source-normalization fixtures.
- Dependencies: P3 sync and units; manual food scope approved.
- Tests: missing nutrients, midnight/DST intervals, duplicate habit occurrence, paused schedules, editable historical logs and inaccessible linked foreign IDs.
- Acceptance: all manual tracking FR-04 through FR-13 work offline, synchronize correctly and appear in export/deletion; no misleading missing-as-zero values.
- Risks: calorie-focused UX, overcomplicated forms and duplicated activity totals.
- Validation checkpoint: daily-use usability walkthrough, accessibility check and health-safety language review.

## P5 — Deterministic progress and reports

- Objective: trustworthy daily/weekly/monthly insight foundations.
- Components: durable job runner, daily/weekly/monthly aggregation, charts/tables, goal progress, initial deterministic patterns and in-app reports.
- Expected files/modules: backend `jobs`, `analytics`, `reports`; mobile `dashboard`, `progress`, `reports`; golden metric fixtures.
- Dependencies: P4, approved formula versions.
- Tests: corrections/deletion during rebuild, source cutoffs, repeated jobs, unequal-coverage averages, goal revisions, stale flags and accessible charts.
- Acceptance: numbers match reviewed fixtures; summary freshness/coverage is visible; worker crash/retry converges without double counting; reports exclude deleted evidence.
- Risks: stale analytics, misleading patterns and unbounded historical scans.
- Validation checkpoint: reviewer independently computes a synthetic month; load-test catch-up after simulated downtime.

## P6 — Local reminders and push

- Objective: dependable best-effort reminders with clear user controls.
- Components: local scheduling, FCM/APNs integration, device management, quiet hours, server due-job dispatcher, inbox and delivery history.
- Expected files/modules: `core/notifications`, `features/reminders`, `notifications`; backend dispatcher/device registry; scheduler test fixtures.
- Dependencies: P4 schedules and P5 durable jobs; correct platform entitlements and selected Vercel plan.
- Tests: DST/travel, permission denial, token rotation, account switch, overlapping dispatchers, unknown FCM outcome, local owner transfer and expired reminder suppression.
- Acceptance: one selected channel per occurrence, opt-out respected, generic payloads, correct deep links and visible local scheduling status on both OS families.
- Risks: OS delivery limits, duplicated display after ambiguous sends and stale offline schedules.
- Validation checkpoint: physical-device matrix in foreground/background/terminated/reboot states; document observed limitations.

## P7 — Text coach, structured memory and personalization

- Objective: safe grounded coaching that improves with confirmed context.
- Components: Responses adapter, context budget/evidence validation, conversation lifecycle, memory/observations UI, extraction suppression, recommendation feedback and confirmed action proposals.
- Expected files/modules: `services/api/src/ai`, shared AI contracts, `features/coach`, `memory`; synthetic evaluation corpus and prompt versions.
- Dependencies: P5 verified summaries, P2 consent/privacy and approved model budget.
- Tests: fabricated history, missing/conflicting data, prompt injection, cross-user tools, deletion/consent during generation, extraction after forgetting, safety routing and ambiguous billed retries.
- Acceptance: grounding/safety thresholds in test strategy; every personal claim traceable or rejected; observations remain distinct; no autonomous mutation or unlimited context growth.
- Risks: plausible unsupported advice, stale memory, privacy leakage and model cost.
- Validation checkpoint: qualified health-safety review plus independent adversarial evaluation before exposing to real users.

## P8 — Production voice coaching

- Objective: realtime voice with server-controlled tools, lifecycle and spend.
- Components: Flutter WebRTC/audio ports, server-brokered SDP, controller runtime, sideband, application captions/control, interruption semantics, usage reservation and watchdog termination.
- Expected files/modules: `services/voice`, shared session contracts, `features/coach/voice`, platform adapters and device test harness.
- Dependencies: P1 transport spike, P7 context/safety and approved ADR-09 runtime choice; no hidden use of beta infrastructure.
- Tests: hostile SDP/data-channel injection, ticket replay, call ownership, controller death, sideband loss, network transitions, barge-in, permission/audio-focus loss and consent revocation.
- Acceptance: permanent key absent from client; no unvalidated tool mutation; session shutdown/cost bounds measured; voice safety and accessibility gates pass on Android/iOS.
- Risks: audio before safety intervention, provider lifecycle changes, resource leaks and unnoticed live calls.
- Validation checkpoint: external-provider/device acceptance and cost test; if failed, full-duplex production remains blocked and reviewed buffered speech is only an interim capability.

## P9 — Health imports, full reports and privacy completion

- Objective: complete optional platform integrations and mature data controls.
- Components: opt-in HealthKit/Health Connect steps/activity/sleep import, source priorities, bounded backfill/deletions; downloadable reports; full export/erase workflows; localization and accessibility completion.
- Expected files/modules: `core/platform/health`, import normalization module, artifact builder, privacy worker/runbooks, localization resources and integration fixtures.
- Dependencies: P4/P5 data rules, P2 privacy and P8 cross-feature lifecycle behavior.
- Tests: overlapping sources, permission revocation, provider deletion, export barrier races, nested account erasure, forgotten evidence suppression and artifact expiration.
- Acceptance: manual use works without health access; no double counts; export covers all user data; account erasure reconciles all stores/jobs; every screen passes accessibility critical tasks.
- Risks: store health-data policy, provider licensing, inconsistent export snapshots and incomplete erasure.
- Validation checkpoint: privacy inventory reconciles schema against export/deletion manifests; store disclosure and localization review.

## P10 — Production hardening and release

- Objective: release and operate the complete application safely on both platforms.
- Components: performance/cost tuning, production IAM/configuration, backups/restore, monitoring/alerts, penetration review, health-safety final evaluation, signed builds and staged rollout.
- Expected files/modules: release workflows, deployment configuration, operational runbooks, release checklist and supported-version policy.
- Dependencies: all earlier acceptance criteria; approved store accounts, support owner and production budget.
- Tests: complete regression, synthetic load plus burst, real-device E2E, key/redaction inspection, disaster recovery, model rollback and server kill-switch drill.
- Acceptance: all FR-01 through FR-32 demonstrably covered; no critical release blockers; both stores' release validation complete; rollback/support procedures exercised and cost envelope approved.
- Risks: store review delays, mobile rollback limitations, unexpected scale and incomplete on-call coverage.
- Validation checkpoint: product/security/privacy/health-safety release signoff; start small rollout, compare actual metrics with targets and pause if thresholds fail.

## Ongoing work after launch

Review provider deprecations, dependencies, safety evaluations, privacy requests, cost per active user and notification quality. Add new integrations only with updated contracts, threat model, consent, deletion and tests. Revisit vector search, queue services or persistence migration only after measured limitations justify them. A production launch does not remove the need for ongoing safety and reliability ownership.
