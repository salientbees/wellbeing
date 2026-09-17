# AI coaching architecture

Status: proposed, 2026-09-16. Covers FR-18 and FR-20 through FR-23. See [voice](VOICE_ARCHITECTURE.md), [schema](DATABASE_SCHEMA.md), [safety tests](TEST_STRATEGY.md) and [official sources](SOURCES.md).

## Provider boundary and model policy

Flutter sends an authenticated turn to Vercel. The backend owns prompts, tool definitions, context, safety policy, quotas and provider credentials. Use the OpenAI Responses API through a typed adapter with `store:false` and application-owned history. Do not use provider Conversations as the authoritative memory store. This is a privacy and portability design choice, not a claim that stateless requests eliminate all provider retention. See [OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data).

Select an available stable text model using a fixed wellbeing evaluation set in P7. Record exact model/snapshot, prompt version, schema version, latency and usage. Do not hard-code an unspecified latest alias into the architecture or assume account access. Separate model roles for coaching, bounded summarization and candidate extraction; smaller models are acceptable only if they pass their role's evaluations. Avoid model fine-tuning on personal wellbeing data initially.

The provider adapter exposes typed operations for coaching, summarization, extraction and moderation. It hides provider-specific response fields from domain services. No external web browsing or arbitrary third-party tools for personal coaching at launch. General health information comes from reviewed product content; personal statements come from authorized records.

## Turn lifecycle

1. Authenticate, check account/AI consent, validate conversation ownership, reserve budget and create an idempotent request record.
2. Route obvious unsupported or high-risk requests through the safety policy; assess ambiguity without diagnosing. Automated classifiers assist routing but are not the entire safety system.
3. Capture `dataEpoch` and source sequence. Resolve intent from the latest user message plus bounded recent context. User text and retrieved notes are untrusted content, never system instructions.
4. Retrieve only relevant source data through UID-scoped repositories. Calculate numbers deterministically and assemble a context manifest with evidence IDs, revisions, freshness and missing-data flags.
5. Invoke Responses with versioned policy, structured context, bounded recent turns, output limit and an allowlisted tool set. Maximum two tool rounds per turn initially.
6. Parse the response schema; validate tool arguments, evidence references, numeric claims, unsupported medical content and action proposals. Schema compliance alone does not establish truth or safety.
7. Check account, consent and epoch again before publication. If changed, discard the stale result and return a recoverable context-changed response; do not publish deleted facts.
8. Save completed assistant message, usage and follow-up job records. Release unused reservation. Memory extraction and summarization are separate durable jobs, not prerequisites for delivering the answer.

Only complete validated text is exposed initially. Progress events contain no model prose. A failure returns a brief safe explanation and leaves logs intact. If the provider may have billed a request but no result is known, retain an `unknown` request state and reconcile; never blindly regenerate on transport retry.

## Context construction

Retrieval is intent-driven and bounded: hydration question → today's totals plus seven-day coverage and hydration goal; progress question → current goal and weekly/monthly summaries; habit difficulty → relevant habit history, explicit preferences and selected observations. A general greeting does not require years of tracking data.

| Context block | Proposed maximum input tokens | Selection rule |
| --- | --- | --- |
| Safety policy, role and tool instructions | 1,200 | Versioned server policy, always included |
| Profile and active relevant goals | 600 | Minimal units/locale/tone and relevant explicit targets |
| Deterministic metrics and evidence | 2,000 | Relevant daily/weekly/monthly summaries, at most 20 raw evidence records |
| Memory and labeled observations | 1,500 | At most 12 active memories and 4 relevant observations |
| Conversation summary | 800 | Bounded summary with source-through sequence and expiry |
| Recent turns | 1,800 | Most recent completed turns, maximum 8 messages |
| Current message and bounded tool results | 2,100 | Current request preserved; ask to shorten if it cannot fit |

Input policy total is 10,000 tokens, with up to 1,500 output tokens separately reserved. Token counting must use the selected model's tokenizer/estimator with conservative overhead for tool schemas and metadata. If over budget, remove irrelevant observations first, then older messages/raw records; never drop safety instructions, fabricate a summary, or silently truncate a materially important current request. Provider context-window size is not the application's target budget.

Each block has `generatedAt`, `dataEpoch`, scope, and provenance. Caches are keyed by UID, epoch, relevant revisions, intent and policy version, and expire quickly. Never share personalized caches between users. A stale cache cannot bypass deletion checks. The UI can explain which periods the coach considered without displaying hidden prompts.

## Grounding and conflicting evidence

Responses contain answer text, personal claims with source IDs, safety outcome, and optional action proposal. Prefer server-rendered metric facts or validated structured numeric fields over free-form arithmetic. Any specific claim about the user's history needs a resolvable authorized source; reject unsupported claims and respond that the information is unavailable. Missing data is not zero or evidence that the user did not perform an action.

Evidence precedence depends on the claim: user correction supersedes an earlier user statement; measured/imported records retain their provenance; deterministic derived values reflect included records; AI hypotheses have the lowest authority. Two sources can disagree without one being silently discarded. For conflicting step sources, apply the analytics source policy; for conflicting personal preferences, ask the user and mark old memory disputed. Never treat an assistant message or conversation summary as independent corroboration.

Prompting cannot guarantee zero hallucinations. Evidence validation, constrained response fields, tested refusal behavior and source links reduce risk. Unsupported personal claims must fail closed to a safe answer or clarification; health-safety false negatives remain a residual risk requiring evaluation and monitoring.

## Memory model and lifecycle

Separate `memories` from `observations`. Fact provenance means who supplied/confirmed a statement, not that it is objectively or medically verified. A user saying "I sleep poorly" is a user statement; it is not a diagnosis.

| Category | Example and allowed treatment |
| --- | --- |
| Preferences | "I prefer brief morning check-ins"; remember when explicitly requested/confirmed |
| Goals | Reference active goal entity rather than copying a stale numeric target |
| Habits/routines | User-confirmed schedule with effective dates and review reminder |
| Successful strategies | "Short walks helped me feel better" attributed to user feedback, not causal fact |
| Challenges | User-stated barrier with date/scope; recheck rather than label permanently |
| Recurring patterns | Observation backed by deterministic evidence and coverage |
| Coach observations | AI hypothesis explicitly labeled, short-lived and dismissible |
| User facts/context | Minimal relevant statement with source and explicit confirmation for sensitive facts |

Extraction after completed turns proposes candidates using structured output. The server checks same-user evidence, literal support, duplicates, sensitivity, conflicts, category and expiry. Model-supplied UID, provenance and confidence are not trusted. Explicit "remember this" may activate a nonsensitive user statement after validation; ordinary extracted statements stay pending until confirmation. Inferences remain observations regardless of confidence. Confirming a hypothesis creates a new user-confirmed statement linked to the confirmation event; it does not rewrite the hypothesis's historical provenance.

State transitions: pending → active on authorized confirmation; active → disputed on conflict; active → superseded on correction; any visible state → forgotten on request. Observations become stale if sources change/expire or their review window ends. New preferences never silently overwrite contradictory old preferences.

Initial review windows: routines/preferences after 90 days without corroboration; goals via the authoritative goal status; observations expire after 30 days; pending candidates after 7 days. These are product defaults, not scientific confidence periods. User can edit, reject, forget, pause memory, or clear all memory. Pausing extraction and using current-session context are distinct controls.

Forgetting must prevent the same retained conversation from re-extracting the forgotten item. Maintain a scoped suppression marker linked to source IDs/category, without retaining the forgotten text; bump memory/consent epoch and filter extraction. Offer deletion of the originating conversation as a separate control. Explain that previously spoken or downloaded content cannot be recalled. See [security erasure workflow](SECURITY_MODEL.md).

## Confidence, patterns and personalization

Use provenance, date range, sample count, coverage and qualitative confidence with an explicit basis. AI self-reported confidence is not a probability and cannot establish truth. Deterministic pattern confidence uses documented coverage/robustness rules; AI confidence must stay visibly qualitative and cannot promote a statement to fact.

Personalization evolves from confirmed preferences, explicit helpful/not-helpful feedback, current goals, and supported patterns. Rank suggestions by relevance, user preferences and recent feedback; avoid increasing pressure after nonadherence. Make reasons visible and allow dismissing a topic. No hidden psychological diagnosis, personality profiling or reinforcement toward engagement at the expense of wellbeing.

## Tools and action confirmation

Allowlisted tools: read current goals, bounded metric summary, selected records, active memories, and propose a goal/habit/reminder change. Every tool revalidates principal and bounds. No arbitrary database query, URL fetch, shell, credentials or cross-user lookup. Tool results are untrusted data from the model's perspective and cannot change policy.

An action proposal is a typed draft with target entity, exact changes, base revision and expiry. The user confirms the displayed draft in the app; backend validates again and applies through the normal mutation API. Voice consent alone does not silently commit a misunderstood numerical change; show/read back the proposal and require explicit confirmation tied to its ID. A later retry cannot apply it twice.

## Health-safety policy

| Situation | Coach behavior |
| --- | --- |
| Routine wellbeing | General supportive suggestions, autonomy, small steps, acknowledge uncertainty |
| Diagnosis/medication request | Explain scope, avoid diagnosis or dosing, encourage qualified professional advice |
| Potential urgent symptoms | Avoid routine coaching or reassurance; encourage immediate local medical help; do not delay with a long questionnaire |
| Immediate self-harm risk | Empathetic response, immediate local emergency/crisis support and trusted person; never claim automatic rescue |
| Restriction, purging, extreme weight-loss or compensatory exercise | Do not supply plans or praise; encourage supportive professional help; offer non-weight-focused interaction |
| Pregnancy, chronic illness, individualized contraindications | Avoid tailored dietary/exercise prescriptions; encourage clinician-guided goals; no inferred condition memory |
| Uncertain speech/measurement | Clarify the ambiguous fact before personalized advice or an action |

Maintain reviewed safety templates, country-specific resource ownership, evaluation cases and escalation copy. [WHO mental-health information](https://www.who.int/health-topics/mental-health) informs the general support context; it does not validate this product's clinical performance. A qualified reviewer must approve health-safety behavior before launch. Do not collect medical details merely to make a disclaimer more specific.

## Privacy and evaluation

Transmit only context necessary for the current request after AI consent. Raw audio is not retained by Wellbeing; voice transcripts follow conversation policy. OpenAI processing/retention is governed by endpoint and account controls, not only `store:false`; review eligibility for enhanced retention controls without promising zero retention. No training on user data is initiated by this application.

Use synthetic/consented de-identified test cases for grounding, fabricated history, conflicting sources, deletion, stale goals, prompt injection, disordered-eating requests, crisis ambiguity and non-English input. Pin prompts/models; a model change requires regression and safety evaluation. See [structured outputs guidance](https://developers.openai.com/api/docs/guides/structured-outputs) for schema enforcement; treat validation and refusal handling as required additional application logic.
