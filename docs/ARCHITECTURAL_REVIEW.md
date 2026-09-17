# Architectural self-review

Status: review of the proposed blueprint, 2026-09-16. No risk is presented as resolved by code or testing that has not happened. See [roadmap](DEVELOPMENT_PLAN.md) for gates.

## Principal assessment

The selected platform is suitable for a modular personal wellbeing application. The largest risks are authoritative backend authorization, custom offline convergence, health-safety behavior, privacy erasure across derived data, and trusted control of realtime voice. These deserve early proof, not late polishing. Firestore scale is less likely to be the first limit than read amplification, per-user contention and AI spending.

One additional runtime is proposed for voice, with a concrete reason and a removal checkpoint. No AWS/Azure/Kubernetes, vector database, microservice decomposition or new queue vendor is assumed. Vercel's current beta WebSocket capability must not be ignored, but production design should not silently depend on its maturity.

## Risk register

| ID / severity | Risk | Mitigation and residual limitation | Owner / checkpoint |
| --- | --- | --- | --- |
| R01 / critical | Firebase Admin bypasses rules; authenticated user accesses another account | Principal-required scoped repositories, no arbitrary paths, nested-reference tests, deny-all direct client rules, penetration review; server bugs remain consequential | Backend/security, P2 and every API PR |
| R02 / high | Custom offline sync loses edits or resurrects deleted data | Atomic local outbox, idempotency, revision conflicts, feed/tombstones, expired-operation reconciliation and property tests; long-offline devices require explicit reconciliation | Mobile/backend, P1/P3 |
| R03 / high | Local SQLite/WAL/backups expose health data | Prove encryption and key lifecycle, inspect physical artifacts, exclude backups and wipe account cache; unlocked/rooted device remains a risk | Mobile/security, P1 |
| R04 / critical | Unsafe or fabricated coaching | Constrained evidence, no diagnosis/dosing, buffered text, reviewed safety policy and adversarial evaluations; cannot guarantee perfect model behavior | AI/health-safety reviewer, P7/P10 |
| R05 / high | Inference becomes a user fact or persists after correction | Separate observations, explicit provenance/confirmation, revision-linked evidence, expiry and suppression markers | AI/backend, P7 |
| R06 / critical | Deletion misses summaries, jobs, artifacts, backups or provider state | Inventory-driven erasure, epoch/exclusions, resumable workers, restore suppression and provider retention disclosure; already transmitted/downloaded data cannot be recalled | Privacy/backend, P2/P9/P10 |
| R07 / high | Voice streams unsafe content before checks | Restrict scope, server monitoring, cancellation and reviewed fallback; realtime cannot promise pre-screening of every spoken word | Voice/health-safety, P8 |
| R08 / high | Provider call outlives controller and burns budget | Server session admission/reservation, lease, watchdog hangup and tested call caps; crash between provider creation and ID persistence needs explicit reconciliation/cost allowance | Voice/backend, P1/P8 |
| R09 / high | Vercel/runtime duration or beta feature mismatch | Separate stable long-lived controller proposal, runtime spike and reevaluation before provisioning; one extra runtime adds operations | Platform, P1/P8 |
| R10 / high | Firestore read amplification, contention and indexes | Per-user bounded feed, coalesced aggregates, index catalog, source caps and hot-user load test; sequence serialization may need later redesign | Backend, P3/P10 |
| R11 / high | Firebase location or project choice conflicts with residency | Resolve launch geography and processor locations before provisioning; region migration may require export/import and downtime | Product/privacy/platform, P0 |
| R12 / medium | Notification duplicate/missing delivery | Single channel owner, occurrence IDs, leases, expiry and unknown-outcome policy; OS push is best effort, exactly once cannot be guaranteed | Mobile/backend, P6 |
| R13 / high | Health import double counts or grants excessive access | Source precedence, nonoverlap normalization, typed opt-in and deletion propagation; platform data quality still varies | Mobile/data, P9 |
| R14 / high | OpenAI spend exceeds estimates or client controls quotas | Persistent worst-case reservations, model allowlist, bounded context/sessions, alerts and server kill switches; vendor billing delay is a residual risk | Platform/product, P7/P8/P10 |
| R15 / high | Sensitive data leaks through Analytics/Crashlytics/logs | Collection consent/default verification, allowlist redaction tests, no health values or transcripts; third-party SDK updates require review | Mobile/platform/privacy, P2/P10 |
| R16 / high | iOS cannot be validated from Windows alone | macOS CI/Xcode, signed build pipeline and physical iPhone testing arranged in P1 | Release/mobile, P1 |
| R17 / medium | Flutter/native plugins break OS updates | Pin stable compatible versions, adapter boundaries, device matrix and scheduled upgrade tests; community plugins may need replacement | Mobile, P1/P10 |
| R18 / high | Aggregates and historical targets become inconsistent | Effective-dated goal/habit/schedule revisions, algorithm versions, dirty-period rebuilds and coverage fixtures | Data/backend, P4/P5 |
| R19 / high | Export snapshot mixes states or blocks tracking too long | Bounded snapshot barrier, queued uncommitted edits, timeout/retry and later large-account strategy; privacy erasure overrides export | Backend/privacy, P9 |
| R20 / high | Tests mock away real provider and platform constraints | Emulator plus real staging IAM/index/provider checks; physical audio/push/accessibility tests; budgeted synthetic evaluations | QA/platform, all gates |
| R21 / high | Unresolved age, jurisdiction, claims or store obligations | Adult general-wellbeing assumption, legal/health-safety/store review before launch; do not claim HIPAA/GDPR/medical-device certification without assessment | Product/privacy, P0/P10 |
| R22 / medium | Future provider/database migration is costly | Typed ports, application-owned history, portable exports, contract fixtures and no Firestore types in domain; migration still needs rewrite of adapters/index strategy | Architecture, each integration |
| R23 / high | Prompt/model/API changes silently degrade behavior | Pin versions where supported, adapter contract tests, source refresh and regression gates; provider deprecation requires maintenance | AI/platform, P7 onward |
| R24 / medium | Accessibility and localization safety gaps | Native assistive-tech testing, reviewed safety translations, chart tables, no voice-only flows | Design/QA/health-safety, every phase |

## Open product and operational decisions

| Decision | Working assumption | Required resolution |
| --- | --- | --- |
| Audience and age | Self-declared adults 18+, independent general wellbeing | P0 product/privacy review before onboarding implementation |
| Markets/residency | No launch country assumed | P0 before Firebase/Storage region selection |
| Scope of weight/nutrition advice | User-selected goals; no prescribed deficits or medical targets | Qualified safety review before P7 |
| Food data | Manual/label entry first; no external catalog license assumed | P4 for manual UX; separate licensing decision for barcode/database additions |
| Auth providers | Email/password plus Apple/Google as platform/product policy permits | P2 provider/store requirements review |
| Languages/accessibility | English-first implementation, localization-ready; launch languages undecided | P0/P9 reviewed copy and real users |
| OS/device floor | Current stable toolchain compatibility, exact floor undecided | P1 dependency matrix and product reach |
| Reports | In-app accessible reports, proposed PDF and JSON/CSV export | P5/P9 format, accessibility and artifact limits |
| Retention | Proposed classes R1–R8 and 35-day backup ceiling | Privacy approval and provider configuration verification before production |
| Scale/budget | Sizing scenario in operations document, not forecast | P0 usage forecast, absolute spend caps and voice allowance |
| Support/incident ownership | Required but no team identities assumed | P10 named owners and response coverage |
| Controller runtime | Cloud Run narrow exception | P1 feasibility, P8 stable Vercel reassessment |

## Consistency review conclusions

The canonical business-data access path is API-only; no other document should imply client Firestore writes or SDK offline synchronization. Raw audio is not retained by Wellbeing; provider processing retention remains separately disclosed. AI facts and observations use different collections and promotion rules. All client-visible server updates enter the change feed. All data stores and operational copies must appear in export/deletion inventories, except explicitly documented content-free restricted security records.

Custom offline synchronization and the voice controller are deliberate complexity, justified by explicit conflict/privacy and server-control requirements. If feasibility testing rejects either, update this blueprint coherently before implementation continues. Do not implement a partial substitute while describing the original production guarantees as achieved.

## Documentation validation record

Read-only checks on 2026-09-16 passed for 16 Markdown files: all required files present; 43 relative document links resolve; one H1 per file; heading progression/spacing, matching code fences, table column counts, final newlines and trailing whitespace pass; all 32 functional requirement IDs and 11 phases P0–P10 are present; every phase specifies objective, components, expected modules, dependencies, tests, acceptance, risks and validation checkpoint. No non-Markdown workspace files were introduced outside the existing Git metadata.

No Markdown linter executable was available, so a read-only Python standard-library check was used without installing tooling or saving a script. `git diff --check` reported no tracked whitespace errors; because the new files are untracked, the explicit Markdown checks are the relevant content validation. Git status shows only README.md and the 15 documentation files as untracked; branch and remote remain unchanged and no commits exist. Mermaid diagrams were reviewed as source, not rendered by a diagram engine.

Application builds, mobile tests, cloud integration tests, security validation and clinical/safety validation are not possible evidence from a documentation-only repository and are not claimed here.
