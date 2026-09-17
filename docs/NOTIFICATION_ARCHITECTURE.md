# Notifications and reminders

Status: proposed, 2026-09-16. Covers local reminders, FCM/APNs push and the private in-app inbox. Notifications are wellbeing conveniences, never emergency or medication-critical alarms.

## Channel ownership

Local notifications support offline routine reminders on a selected primary device. Server push supports summary-ready notices, account notices and reminders explicitly configured for push. Every reminder occurrence has exactly one selected delivery mode and, for local mode, one primary device. Do not send an automatic push fallback for a possibly displayed local notification; the OS cannot reliably prove non-delivery.

The backend owns recurrence and preferences. Flutter holds a rolling local schedule after the server acknowledges the reminder. Locally created offline reminders may run on that device with a clearly pending state; the backend must not activate parallel push while they are pending. Changes synchronize with revision checks. Multi-device scheduling explicitly transfers ownership, cancels the old schedule where possible and explains that an offline old device may still display a previously scheduled reminder.

## Durable scheduler

Vercel Cron periodically invokes a protected dispatcher. Production requires a plan/cadence supporting the selected target, initially a one-minute tick for push scheduling; verify plan capabilities before provisioning. Scheduler timing is best effort. It queries indexed due jobs, claims with a lease transaction, checks current account/consent/preferences/schedule revision, creates or reuses the deterministic notification occurrence, dispatches and records the outcome.

After each occurrence, calculate and persist the next due occurrence. A periodic reconciliation pass detects missing next jobs, expired leases and schedule revisions. Do not scan every user each minute. Batch by due time with bounded concurrency and execution deadline. [Vercel Cron management](https://vercel.com/docs/cron-jobs/manage-cron-jobs) documents lack of automatic retry and possible overlapping work; persistent leases and retries are application requirements.

Use `occurrenceKey = reminderId + scheduleRevision + intendedLocalDateTime + timeZone + channelOwner`. Hash it for document IDs. It identifies the logical occurrence, not a retry. A reschedule suppresses unclaimed occurrences from older revisions; claimed delivery checks revision again just before send. Jobs include no health details.

## Timezones and quiet hours

Store recurrence as local wall time plus IANA timezone, not a fixed UTC offset. `zoneMode=fixed` stays in the chosen zone; `followProfile` recalculates future occurrences after the user confirms a profile zone change. Device timezone change prompts reconciliation; historical logs never shift automatically.

Policy proposals: spring-forward nonexistent time → next valid local instant; fall-back duplicated time → first occurrence only. Record that resolution in the occurrence. Quiet hours spanning midnight are supported. If due time falls in quiet hours, move to the end of quiet hours only when still within the occurrence's two-hour usefulness window; otherwise skip. Weekly report-ready pushes may defer longer, at most 24 hours. Do not send a backlog of old hydration reminders after offline recovery.

Preference changes cancel/recalculate future occurrences. Push checks latest preferences immediately before send. Local cancellation is applied on the device and acknowledged to the server; a disconnected device may retain old scheduled notifications until it next runs. The UI must not promise instantaneous cross-device cancellation.

## Token and permission management

Ask for OS permission when enabling a useful reminder, not on first launch. Register one device ID per installation/account association. Upsert refreshed FCM token and timestamp, app version and permission state. Remove associations on logout and invalid-token response, and reconcile staleness periodically. If the same installation changes account, detach the previous association before activation.

Use [Firebase token-management guidance](https://firebase.google.com/docs/cloud-messaging/manage-tokens) for refresh/staleness handling. Never treat a push token as authentication or return it in ordinary device reads. FCM/APNs setup, iOS capabilities and Android permission behavior require device validation. Foreground/background/terminated delivery paths differ and must be tested. Silent/data-only push cannot guarantee background execution.

## Payload, inbox and deduplication

External notification contains generic localized template text, opaque notification ID and an allowlisted route target. No weight, mood, food name, goal value, AI quotation or diagnosis in lock-screen text. User opens the app and authenticates to load details. Inbox records remain available even if push is denied or lost.

Server transactionally creates one occurrence/delivery record; repeated jobs reuse it. Client deduplicates by notification ID and uses stable local OS notification IDs. For remote reminders use platform collapse/replacement identifiers where applicable. These reduce duplicate display but do not establish exactly-once delivery.

A network failure after FCM accepted a send but before acknowledgment is ambiguous. Record `unknown`; reconcile metadata if possible and avoid aggressive resend. For routine reminders, prefer a missed duplicate-prone send over repeated lock-screen notifications. For approved retryable failures, bounded retry uses the same logical ID. OS-rendered notifications may still duplicate; disclose this as a tested residual constraint, not a guaranteed impossibility.

## Delivery state and retry policy

States: planned → leased → submitted → acknowledgedByClient/opened when observable; or retryDue, unknown, expired, cancelled, invalidToken, failed. FCM success means provider accepted the message, not that the user received or read it. Distinguish these metrics.

Retry transient errors with jittered exponential delay, at most five attempts, stopping at occurrence expiry. Respect provider Retry-After and global rate caps. Invalid/expired token errors deactivate that token; malformed payloads fail without retry and alert engineering. Keep a bounded dead-letter view and operator retry command that rechecks expiry/opt-out rather than blindly resending.

## Local scheduling constraints

Maintain a rolling schedule window within current OS/plugin limits, initially the next seven days and at most 32 occurrences per device. Refresh on launch, schedule change, timezone change and permission changes. Do not promise exact alarms or unlimited pending reminders. Request special exact-alarm permission only if a future justified product requirement and store policy permit it; ordinary wellbeing reminders should tolerate delay. See the [local notifications maintainer guidance](https://pub.dev/packages/flutter_local_notifications).

Local reminders work without backend connectivity after scheduling; new server changes require sync. Reboot, app reinstall, battery optimization and permission revocation have platform-specific behavior. Surface permission/schedule status in settings, with a safe test reminder action during implementation.

## Verification and metrics

Automate recurrence fixtures for DST, leap years, month boundaries, overnight quiet hours, travel and concurrent dispatch. Test opt-out between lease and send, duplicate job execution, FCM timeout-after-accept, token rotation and device account switch. Physical devices verify actual notification display and tap routing across lifecycle states.

Monitor due-job lag, accepted/error/unknown counts, expired reminders, invalid-token rate, deduplication rate and preference-to-cancellation latency. Never log payload text. Delivery metadata/inbox expire after 30 days unless a minimal security record has a separately approved retention purpose.
