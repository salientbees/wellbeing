# Test and validation strategy

Status: proposed, 2026-09-16. No application tests have been implemented or run in this documentation phase. This strategy defines the evidence required before production.

## Test layers and ownership

| Layer | Automated coverage | Manual / specialist coverage | Gate |
| --- | --- | --- | --- |
| Pure unit | Units, date boundaries, recurrence, numeric validation, metrics, revisions, memory state transitions, quota reservations | Domain formula review | Every PR |
| Flutter controller/widget | Riverpod overrides, form errors, all loading/empty/offline/conflict states, route guards and semantics | Visual hierarchy and language review | Every PR |
| Local persistence | Cache/outbox atomicity, migrations, crash/reopen, expired cursor rebuild, encryption-key loss | Inspect real device database/WAL/temp files and backups for plaintext | P1/P3 and release |
| API contract | Every route, schema boundary, unknown fields, pagination, error mapping, idempotency and version compatibility | Review public API ergonomics | Every PR |
| Firebase rules | Anonymous/user A/user B denied direct Firestore and Storage reads/writes; no collection-list loopholes | Deployed IAM/rules audit | Every PR and deploy |
| Backend isolation | User A cannot access B's records, nested messages, references, downloads, devices, jobs or voice sessions | External penetration review before launch | Every PR |
| Integration | API + Emulator Suite + local worker, aggregate invalidation and job leases | Real staging integration for indexes, IAM, FCM and provider behavior | PR subset; nightly full |
| AI service | Fixed synthetic contexts, schema failures, missing evidence, stale memory, conflicts, refusals, usage and cancellation | Human grounding/helpfulness review | Prompt/model changes |
| AI safety | Diagnosis/dosing requests, dangerous restriction, self-harm ambiguity, prompt injection and fabricated history | Qualified health-safety reviewer; multilingual red team | P7 and release |
| Voice | State machine, transcript/event dedup, controller lease loss, quota termination and ownership | Physical device audio, interruptions, accents, noisy rooms, Bluetooth and actual provider behavior | P8 and release |
| Notifications | DST/quiet hours, lease races, stale revisions, retries, unknown sends, opt-out and token churn | OS display/tap tests in foreground/background/terminated states | P6 and release |
| Offline/recovery | Airplane mode, process kill after local acknowledgment, two-device conflict, >30-day queue, resync and account switch | Low-storage/battery/OS termination testing | P3 onward |
| Accessibility | Semantics, target sizes, text scaling, contrast fixtures and chart table availability | VoiceOver, TalkBack, switch control, reduced motion and usability testing | Every feature / release |
| Mobile E2E | Sign-in → track → sync → progress → coach → reminder → export/delete | Store build/install/upgrade, native permission flows | Nightly/release |
| Security | Dependency/secrets/static scans, auth fuzzing, replay, oversized inputs, URL/HTML injection, logging redaction | Threat-model review and pen test | PR/release |
| Performance | API load, one-user write contention, many-user scheduler, outbox drain, context/read budget, voice concurrency | Midrange physical-device battery/memory/audio experience | P10 |
| Regression | Golden metric fixtures, contract compatibility, saved bug cases, prompt/model baselines | Risk-based exploratory checks | Every release |

## Essential scenario sets

**Identity and isolation:** Unverified email cannot access AI; revoked/expired/wrong-project tokens fail; App Check debug token fails in production; changed UID in body rejected; nested evidence and artifact IDs never escape principal scope; account linking does not merge unrelated histories; account deletion prevents in-flight writes.

**Data and sync:** A server commit followed by lost HTTP response replays without duplicate logs; a partially successful bulk request is correctly reconciled; a tombstone beats an old pending update; a snapshot concurrent with new/deleted records converges; clocks shifted forward/backward do not corrupt ordering; stale operations require review; imported duplicate steps and source deletions produce correct totals.

**Privacy:** Delete a source during AI generation and report creation; neither result may reveal it. Forget a memory while retaining its source conversation; extraction must not recreate it. Clear all AI memory, revoke processing, and verify local/server caches, jobs and voice termination. Delete an account with nested messages and artifacts, retry halfway through, then restore a backup and verify the suppression ledger before access. Repeat for record, category and date-range erasure using a backup predating the request; deleted sources and derivatives remain absent while unrelated and legitimate post-cutoff records survive. Crash before and after recovery-copy acknowledgement, replay duplicate chunks, and simulate missing manifests or key versions: completion/reopening must fail closed until reconciled.

**AI grounding:** Ask about a day with no data; the answer must acknowledge missingness. Supply contradictory user statements and device records; the coach must state the conflict or ask. Include malicious instructions inside a food note or transcript; no privilege or tool scope changes. Numeric claims must match source values and units. A summary cannot act as proof for its own invented statement.

**Voice:** End call from another device; revoke consent while speaking; kill controller after call creation but before sideband ready; lose sideband while WebRTC remains active; watchdog must terminate within the tested bound. Test interrupt/truncation so unheard content is not persisted as heard. Verify denied microphone, phone-call interruption, screen lock, headset unplug and background app transitions.

**Scheduling:** Two dispatchers lease the same due occurrence; one logical delivery record results. Simulate accepted FCM call with lost acknowledgment; do not blindly send five duplicates. Test follow-profile travel, fixed timezone, DST folds/gaps, local primary-device transfer and permission denial without loss of inbox history.

## Test environments and fixtures

Local and CI use synthetic data and Firebase emulators, a fake OpenAI adapter, fake FCM and fake clock. Never use copied production health data. Emulator success does not establish production indexes, IAM, App Check, quotas or push behavior. Test/SIT uses isolated real services and strict spend caps; staging uses release candidates and synthetic/explicitly consented tester data.

Maintain versioned JSON fixtures for APIs and metrics, plus de-identified/synthetic AI evaluation datasets with expected evidence and safety classes. Reproducible seeds, pinned model/prompt versions and saved failure metadata support debugging without logging real user conversations. Real provider evaluation is a controlled job, not run unbounded on every small documentation PR.

## Release thresholds

Initial gates are proposals to validate in P0/P1, then enforce consistently:

- All authorization, privacy, accounting and deterministic calculation cases pass; no unresolved critical/high exploitable security defects.
- No known critical health-safety failure in the release evaluation set. A passed set is not proof of universal safety; human review and monitored rollout remain required.
- At least 95% evidence-grounded personal claims on the reviewed broad evaluation corpus, with 100% rejection of deliberately missing/foreign evidence fixtures. Report the corpus size and uncertainty, not a bare percentage.
- All Tier-1 user journeys pass on both supported OS families and at least one low/midrange Android device; accessibility critical tasks pass with screen reader and large text.
- Meet agreed p95 latency/offline targets from [requirements](PRODUCT_REQUIREMENTS.md); test at expected launch load plus a 3x burst, and sustained scheduler catch-up after outage.
- Successful export, active-store deletion and restore drills with recorded elapsed times; encrypted-cache inspection passes.
- Voice call shutdown, spend reservation and controller-failure bounds pass; otherwise voice remains gated and full product completion is not claimed.

Coverage reports are diagnostic. Aim initially for 90% branch coverage of critical pure domain policies, but do not substitute coverage percentages for adversarial scenarios. Avoid snapshot tests that merely freeze incidental widget structure or mocks that duplicate the implementation.

## CI execution and regression control

Fast formatting/static/unit/widget/API/rules checks run on pull requests. Emulated integration runs on trusted PRs with no production secrets. Nightly suites run broader emulator and real-device/provider cases within budgets. Release candidates run staging E2E, signing/build, migration, accessibility, privacy, performance and security checks.

Any escaped defect becomes a targeted regression case. Flaky tests require an owner and expiry for quarantine; critical isolation/privacy tests cannot be bypassed as flaky. Store redacted test reports and synthetic screenshots only. Manual signoffs record build, OS/device, tester, scenario and outcome, and are required artifacts of release approval.
