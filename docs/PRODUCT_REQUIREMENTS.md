# Product requirements

Status: proposed architecture baseline, 2026-09-16. See [system architecture](ARCHITECTURE.md) and [development plan](DEVELOPMENT_PLAN.md).

## Product intent and scope

Wellbeing helps a person record daily wellbeing, understand long-term changes, and choose manageable actions with an AI coach. Support Android and iOS equally. Daily tracking must remain useful when AI is unavailable or disabled. Do not frame missed goals as failure, reward restriction, or treat weight loss as every person's desired outcome.

Initial audience assumption: adults aged 18 or older using the app independently for general wellbeing. Age eligibility is an onboarding declaration, not identity verification. Launch countries, languages, accessibility testing cohort, supported OS floor, expected scale, budget, and commercial model remain product decisions. Do not infer them from the developer's location. See [review decisions](ARCHITECTURAL_REVIEW.md).

The complete target includes every module below. Phased delivery changes implementation order, not the final scope. First production release requires the voice, privacy, safety, offline and operations gates; a tracking-only internal pilot is not completion.

Out of scope initially: diagnosis, prescribing, clinician workflows, insurance claims, social feeds, advertising profiles, autonomous purchases, medical-device integration, continuous background listening and autonomous changes to goals. Food photo estimation, barcode databases, wearables and external calendars are extension points; manual entry is required regardless of integrations. Basic opt-in HealthKit/Health Connect imports for steps/activity and sleep are planned after manual tracking.

## Functional coverage and acceptance

| ID | Module | Required behavior and acceptance | Delivery phase |
| --- | --- | --- | --- |
| FR-01 | Authentication and onboarding | Email/password verification/reset; Google and Apple sign-in where enabled; safe linking; age eligibility, units, timezone and separate consents; skip optional fields | P2 |
| FR-02 | Profile | Edit preferred name, locale, units, timezone and coaching tone; no compulsory exact birth date or sex | P2 |
| FR-03 | Goals | Create, pause, revise and complete metric or behavior goals; explicit milestone acknowledgments and versioned target history | P3 |
| FR-04 | Weight | Log/edit/delete dated weight; kg/lb display; chart with missing-data treatment and optional hiding | P3 |
| FR-05 | Body measurements | Typed circumference measurements, side/location and cm/in conversion; no compulsory photos | P3 |
| FR-06 | Food/nutrition | Manual foods/portions, optional energy/macros with source and estimate labels; totals preserve unknown values | P4 |
| FR-07 | Hydration | Quick add, edit and daily total; user-chosen target; no universal medical target | P3 |
| FR-08 | Steps/activity | Manual steps/distance, source attribution; opt-in platform import and duplicate/source policy | P4/P9 |
| FR-09 | Exercise/workouts | Type, start/end, duration and optional effort; distinguish workout from all-day activity | P4 |
| FR-10 | Sleep | Intervals, naps, self-reported quality; cross-midnight and overlap rules | P4 |
| FR-11 | Mood | Ordinal self-rating and optional note/tags; neutral language and explicit missing values | P4 |
| FR-12 | Habits | Schedule, pause, complete/skip and target quantity; consistency uses due days | P4 |
| FR-13 | Daily check-in | Short optional prompts, one check-in per local date; links existing logs without double counting | P4 |
| FR-14 | Dashboard | Today's state, quick actions, sync/freshness indicators and next scheduled action | P3/P5 |
| FR-15 | Calendar/scheduling | Day/week views, recurring routine and one-off entries; no external calendar write by default | P4 |
| FR-16 | Reminders | Local scheduled notifications and server reminders with explicit delivery ownership | P6 |
| FR-17 | Push notifications | Permission-aware, generic payload, preferences, inbox and deduplication | P6 |
| FR-18 | AI text coach | Grounded multi-turn conversation, safety routing, cancel/retry and sources for personal claims | P7 |
| FR-19 | AI voice coach | Visible microphone state, captions, interrupt/end, network recovery and text fallback | P8 |
| FR-20 | AI memory | View, confirm, correct, reject, forget and disable; inferences never become facts automatically | P7 |
| FR-21 | AI context construction | Bounded relevant evidence, provenance, freshness, exclusion and consent checks | P7 |
| FR-22 | Pattern detection | Deterministic candidate patterns with coverage and date ranges; user can dismiss | P5/P7 |
| FR-23 | Recommendations | Small optional suggestions, reasons and feedback; confirmation before changes | P7 |
| FR-24 | Progress analytics | Daily/weekly/monthly calculations, metric charts and coverage labels | P5 |
| FR-25 | Reports | Accessible in-app report plus user-requested downloadable summary; deterministic values separated from interpretation | P5/P9 |
| FR-26 | Settings | Units, theme, locale, notifications, integrations, accessibility and consent | P2/P9 |
| FR-27 | Privacy/data controls | Export, record/range/account deletion, conversation/memory controls, local cache wipe | P2/P7/P9 |
| FR-28 | Accessibility | Screen reader, text scaling, contrast, motor access, captions and reduced motion | All |
| FR-29 | Error handling | Recoverable typed errors, preserved drafts, actionable retry and no silent data loss | All |
| FR-30 | Observability | Redacted operational metrics, crash capture and alerts independent of optional product analytics | P1/P10 |
| FR-31 | Security | Tenant isolation, validated mutations, secure keys, app attestation and abuse controls | All |
| FR-32 | Testing | Automated test pyramid plus physical-device, accessibility and safety review | All |

## UX hierarchy

Use five primary tabs: **Home**, **Track**, **Coach**, **Progress**, **Plan**. Profile/settings is consistently reachable from Home and the global account control.

| Area | Screens and navigation |
| --- | --- |
| First use | Welcome and wellbeing scope → eligibility → sign in/create account → consent → optional profile/goals → Home; request microphone/notifications/health access only at use |
| Home | Daily overview, incomplete/synced status, check-in, quick hydration/weight/mood, next reminder, one optional insight |
| Track | Metric chooser → quick entry → history → detail/edit/delete; exercise and sleep interval editors; recent foods and saved portions |
| Coach | Conversation list → text conversation; voice entry, transcript/captions, evidence drawer, proposed actions and memory controls |
| Progress | Date range → metric charts and accessible tables → goals/milestones → reports; explicit data coverage |
| Plan | Calendar → schedule detail; goals → goal detail; habits → habit detail; reminders and quiet-hour settings |
| Settings | Profile, units/timezone, appearance/accessibility, notifications, integrations, AI/memory consent, export/deletion, help and account |

Keep routine entry to a few taps, allow undo, avoid judgmental streak-loss copy, and make weight/nutrition displays optional. Never use push text that exposes weight, mood, food or conversation contents. User can review and cancel any AI-suggested mutation before it reaches the domain API.

## Nonfunctional targets

These are initial testable targets, not measured results or provider guarantees. Validate on defined midrange Android and supported iPhone devices in P1/P10.

| Area | Proposed target |
| --- | --- |
| Local entry | Persist acknowledged offline entry in under 300 ms p95; survive process termination |
| Cached Home | Usable within 2 seconds p95 after warm launch |
| API | Non-AI requests under 1 second p95 in selected launch region; 99.9% monthly availability target |
| Synchronization | Begin within 5 seconds of foreground connectivity; drain 100 ordinary queued operations within 30 seconds under reference network conditions |
| Text coaching | Safe completed response within 15 seconds p95 on reference prompts; visible progress and cancel; 30-second initial request deadline |
| Voice | Session ready within 5 seconds p95; response audio within 2 seconds p95 after turn completion on reference network; document device/network variance |
| Privacy | Immediate logical exclusion on confirmed deletion; active-store erasure target 7 days; backup expiration target 35 days subject to configured provider policy |
| Recovery | Proposed server RPO 24 hours and RTO 8 hours; unsynced local entries excluded from server recovery guarantee |
| Accessibility | WCAG 2.2 AA-informed mobile design; pass native TalkBack/VoiceOver tasks, 200% text scaling and contrast checks |

## Health-safety product behavior

The app is not an emergency service or a substitute for medical care. The coach must decline diagnosis, medication selection/dosing and dangerous instructions. For potentially urgent symptoms or immediate self-harm risk, stop ordinary coaching, respond empathetically and direct the person to immediate local emergency help or trusted human support. Show a location-appropriate, maintained help resource only when locale/country is known; do not invent a number or claim help was contacted.

For non-immediate concerns, encourage qualified professional support without diagnosis or certainty. Weight/nutrition coaching must avoid restrictive, compensatory or extreme plans and defer individualized advice in sensitive circumstances such as pregnancy or disordered eating. No condition inference is stored as a user fact. All scripts require qualified health-safety review before release; see [AI safety](AI_ARCHITECTURE.md).

## Decisions needed before launch

Product owner approves countries, age scope, data residency, retention, monthly spending ceiling, support model, nutrition data licensing, report formats and translations. These decisions do not block documentation; they are explicit gates in the roadmap. Do not advertise clinical outcomes or legal compliance based on this blueprint.
