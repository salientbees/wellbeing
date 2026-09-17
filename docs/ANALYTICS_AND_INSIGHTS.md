# Progress analytics, patterns and reports

Status: proposed algorithm baseline v1, 2026-09-16. Deterministic numbers are the authority; AI interprets supplied values and cannot invent calculations.

## Time, completeness and units

Store UTC instants plus recorded localDate, IANA timezone and offset. Daily summaries use that localDate; weekly summaries use the profile's configured week start and snapshot the boundary policy. Monthly summaries use calendar months, not 30-day intervals. Travel does not silently rebucket old logs. Explicit corrections invalidate affected old and new periods.

Null means unknown, zero means explicitly measured/reported zero, and absence means not logged. Present count of recorded days and expected days alongside every mean/consistency result. Partial food/macronutrient data cannot be displayed as a complete intake total. Convert canonical units only for display; round at presentation, not each intermediate arithmetic step.

## Deterministic metric definitions

| Metric | v1 calculation | Coverage and limitations |
| --- | --- | --- |
| Daily weight | Median of valid nondeleted measurements on that local date | Show source count; one day is one daily representative |
| Weight trend | Rolling seven-calendar-day mean of daily representatives; weekly change compares means of adjacent seven-day windows | Require at least three recorded days in each window; otherwise insufficient data; no interpolation |
| Body measurement trend | Last recorded value by site/side and change from selected baseline | Compare same site/unit; display time gap and do not infer fat loss |
| Food/energy/macros | Sum consumed-item normalized totals per day | Report known subtotal plus count of items with missing nutrients; no calorie goal auto-generated |
| Hydration total | Sum volumeMl for logged beverages within day | No medical adequacy claim |
| Hydration consistency | Days meeting the user's effective hydration goal divided by days the goal was active and due | Show logged coverage separately; unknown days are not called confirmed failure |
| Steps/distance | Sum normalized nonoverlapping intervals from selected daily source policy | Never sum overlapping phone/watch cumulative totals |
| Exercise duration | Sum union of workout time intervals, with type breakdown | Do not add all-day activity duration/steps a second time |
| Exercise consistency | Scheduled exercise occurrences met divided by due occurrences under user's goal | If no schedule, show days with logged exercise, not invented compliance |
| Sleep duration | Union of sleep intervals minus known awake time, separated main sleep/naps; assign to wake date | Unknown awake time labeled; overlaps across sources resolved before aggregation |
| Sleep trend | Seven-day mean/median duration and bedtime variability over recorded main sleeps | At least three records for a trend; no sleep-disorder inference |
| Mood | Distribution of ordinal ratings; daily median and recorded-day counts | Avoid claims of clinical scores or precise causal changes from an ordinal scale |
| Habit consistency | Completed due occurrences / eligible due occurrences; quantity goals capped at 1 per occurrence | Paused/not-yet-started days excluded; explicit skip counts as unmet, missing remains unknown in UI |
| Activity consistency | Days meeting effective user-defined steps/activity goal / active goal days | Source coverage and permission gaps visible |
| Numerical goal progress | For monotonic target: `(current - baseline) / (target - baseline)`, clamp to 0..1 for progress bar only | Show true values separately; reject zero denominator; effective target revision used |
| Maintain goal | Fraction of eligible observations inside user-defined range | Requires a range, cannot use monotonic formula |
| Milestones | First confirmed crossing of configured threshold, recorded once per goal revision/milestone | Corrections may revoke an unearned milestone; no repeated push on rebuild |

For habits and consistency, show both a conservative due-period completion rate and logging coverage. Example: 3 completed, 1 explicit skipped, 3 unknown among 7 due days gives 3/7 completion with 4/7 known status; never label all four remaining days as known nonadherence. A streak is a secondary optional visualization, not the primary wellbeing score.

## Source normalization and duplication

Imported records carry platform/source IDs; upsert by hashed source identity and propagate source deletions. User chooses a preferred daily source, with a documented default ranking established during P9. Within a metric/day use one authoritative cumulative source or nonoverlapping interval samples, not both. A manual replacement explicitly overrides the selected period; a manual addition is allowed only for a nonoverlapping interval.

Activity and exercise describe different views of the same day and are not necessarily additive. Health-platform permissions may be partial; missing import access must not zero historical data. Preserve provenance and provide a source-detail screen. Import only data types enabled by the user, with bounded backfill and ingestion batches.

## Aggregation pipeline

A tracking mutation commits dirty markers for affected daily/weekly/monthly periods with source sequence and algorithm version. Workers coalesce multiple writes, load bounded records, compute deterministically, and publish only if source sequence/epoch is still compatible. If changed during processing, keep dirty status and rerun. Idempotent upserts replace an entire summary rather than incrementing totals that may double-count retries.

Daily summaries drive Home; weekly/monthly summaries compose daily metrics only where mathematically valid. Means retain sum/count or sufficient statistics; do not average averages with unequal coverage. Sleep intervals crossing a boundary require original intervals or correctly partitioned statistics. Keep algorithm version and recompute old periods on calculation fixes with visible report versioning.

Nightly reconciliation checks recent periods and stale jobs; larger historical rebuilds run in bounded batches. Stale summaries are labeled, excluded from AI if materially misleading, and never silently described as current. [Firestore write-time aggregation guidance](https://firebase.google.com/docs/firestore/solutions/aggregation) informs the choice to precompute; this project uses its own durable backend job path rather than adding database triggers.

## Pattern detection

Start with a small reviewed deterministic set: difference in logged mood between days with/without self-reported exercise; sleep duration versus next-day logged mood; time-of-day habit completion; repeated missed logging periods. Require an observation window of at least 28 days, at least 14 paired recorded days for paired analysis, and adequate observations in each comparison group (initially five). These are engineering suppression thresholds, not proof of statistical validity.

Patterns include algorithm, period, counts, effect direction/magnitude, missingness and confounder caveat. Use ordinal-appropriate comparisons for mood. Do not mine hundreds of combinations and present the strongest as a discovery. Limit candidate families, require repeat evidence and allow dismissal. No causality claims, disease detection or automated medical escalation from a correlation.

AI may turn a deterministic candidate into readable language or propose a labeled hypothesis, but cannot change the underlying values or invent evidence. Observations carry expiry and source references; deleting or correcting records invalidates them. Self-reported successful strategies remain user feedback, not causal proof.

## Reports

Daily report summarizes known totals and gaps; weekly report compares equivalent periods and active goals; monthly report shows longer trends, milestones and coverage. All have selected timezone, source cutoff, algorithm version and data freshness. Accessible in-app tables are required; proposed PDF summary and JSON/CSV export are implementation choices to validate in P9.

AI commentary is an optional clearly labeled section with evidence links and uncertainty. The report remains useful without AI consent. Report generation uses a consistent snapshot/cutoff strategy, not an unbounded live query while edits occur. Private artifact links expire; regenerating after source changes creates a new version. No automatic emailing or sharing with anyone.

## Test fixtures and quality gates

Fixtures cover unknown vs zero, partial nutrients, kg/lb conversion, same-day multiple weight entries, cross-midnight sleep, DST, overlapping workouts, duplicate imports, paused habits, goal revision, baseline equal to target and deletion after report creation. Property tests assert order independence, replay idempotency, unit conversion tolerance and totals consistent with included sources. A qualified reviewer evaluates interpretation language separately from arithmetic tests.
