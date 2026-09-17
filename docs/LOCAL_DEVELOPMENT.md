# Local development and P1 validation

## Installed Windows toolchain

- Flutter 3.47.4 stable / Dart 3.13.3: `C:\development\flutter` (official archive, SHA-256 checked).
- Android Studio Quail 4, 2026.1.4.7: `C:\development\android-studio` (official ZIP, SHA-256 checked).
- Bundled Java: JBR 25.0.3, explicitly configured in Flutter.
- Android SDK: `C:\development\android-sdk`; user `ANDROID_HOME` and PATH configured.
- Platforms API 36 and plugin-required API 35, build-tools 36.0.0, platform-tools 37.0.1, NDK 28.2.13676358, CMake 3.22.1, emulator 37.1.11, Google APIs x86_64 API 36 image.
- Virtual device: `wellbeing_api36`; Windows Hypervisor Platform acceleration passed.
- Existing Node 24.13.1 / npm 11.6.4. Node version and dependencies are pinned; no cloud project selected.

Restart terminals/editors opened before PATH was updated. Installation archives remain outside this repository in `C:\development`.

The required stable Android SDK license is accepted. `flutter doctor -v` still warns about six unaccepted licenses for unused Google TV, XR, ARM translation, preview, Glass and MIPS packages. Missing Visual Studio only affects Windows desktop builds, which are outside the mobile scope. Do not install these extra products just to remove diagnostics.

JBR 25 on this Windows installation failed with `Unable to establish loopback connection` when using its default temporary socket path. The process-local wrapper below uses the verified `C:\development\java-tmp` directory; override with `WELLBEING_JAVA_TMP` on another machine. This is not a machine-wide Java configuration change.

## Commands from the repository root

```powershell
npm ci
npm run check
npm run contracts:check
npm test
$env:JAVA_HOME = 'C:\development\android-studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
.\scripts\with-local-java.ps1 npm.cmd run test:rules

Push-Location apps/mobile
flutter pub get --enforce-lockfile
flutter analyze
flutter test
..\..\scripts\with-local-java.ps1 flutter.bat build apk --debug
..\..\scripts\with-local-java.ps1 flutter.bat test integration_test/foundation_test.dart -d emulator-5554
Pop-Location
```

The Firebase test command uses **demo-wellbeing**, loopback hosts and no credentials. It does not create a Firebase resource. The common OpenAPI schemas are generated from the runtime Zod schemas: run `npm run contracts:generate` after changing them. Local API implementation now includes bootstrap, account reads, bounded resource pages, mutations, change-feed and snapshot replay. The health endpoint reports liveness only.

Start the emulator through Android Studio Device Manager or `flutter emulators --launch wellbeing_api36`. For the verified headless configuration use the official emulator with `-avd wellbeing_api36 -no-window -no-audio -no-snapshot -gpu swiftshader -feature -Vulkan -memory 4096 -cores 4`.

## Validation recorded on 17 September 2026

| Check | Result |
| --- | --- |
| Flutter/Dart version and SDK archive checksums | Passed |
| Emulator hardware acceleration and API 36 boot | Passed; WHPX usable, Android boot completed |
| `flutter doctor -v` | Flutter, Windows, network and Android device detected; two diagnostic categories remain: unused SDK licenses and Windows-only Visual Studio |
| `flutter analyze` | Passed, no issues |
| `flutter test` | 3 tests passed: encrypted persistence/rollback/reopen/owner/key checks, tab navigation, 200% text and accessibility guidelines |
| Android integration test | 1 test passed on emulator-5554: navigation, platform secure-storage key round-trip/deletion, encrypted SQLite/WAL sentinel inspection and reopen |
| Android debug build | Passed; `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk` |
| Normal application install and launch | Passed with `flutter run --debug --no-resident`; screen visually inspected |
| Packaged Android manifest | Verified `allowBackup=false`, `fullBackupContent=false` and extraction-rules reference |
| TypeScript and contract generation drift check | Passed |
| Node contract and HTTP tests | 4 tests passed |
| Firebase emulator rules | Passed anonymous/owner/other-user read, write, delete and list denials for Firestore and Storage |
| Documentation links and JSON parsing | Passed |
| Git | Still main with original remote; no commits or pushes made; initial repository files remain untracked |

The Android installer required retries: legacy SDK Manager stalled on large downloads, and the new Android CLI returned abnormal exit codes after extraction. Installed package registration and actual compiler, build, boot and integration checks were used to verify the outcome. These are local Windows observations, not a change to the application architecture.

## Foundation boundaries and remaining gates

The five-tab Material 3 shell supports light/dark system themes and externalized English strings. It deliberately shows no fabricated user records or AI responses. Firebase email authentication/verification, onboarding, encrypted account workspaces, manual tracking forms/history, goals/planning forms, dashboard and deterministic progress screens are now implemented. End-to-end coverage and remaining production gates are recorded below. The application identifier `com.salientbees.wellbeing` is provisional until release ownership and store registration are confirmed.

The storage spike encrypts complete JSON payloads using AES-256-GCM before writing them through Drift. Account, row and payload-kind bindings are authenticated. SQLite contains opaque identifiers and encrypted payloads; it is **not whole-file SQLCipher encryption**. It demonstrates atomic projection/outbox persistence, rollback, reopen, wrong-key/owner rejection and plaintext sentinel checks. It is not connected to application repositories. Production key lifecycle, query performance, migrations, crash/process-death recovery and backup/restore still need their documented P1/P3 device gates. Android integration uses platform secure storage for a synthetic key; no health data or permanent service key is used.

Android app backup and device transfer are excluded in the manifest and extraction rules. This configuration does not substitute for physical-device backup inspection. iOS secure-storage accessibility, backup exclusion, signing and execution still require macOS/Xcode and an iPhone.

P1 cannot be marked complete until macOS/iPhone access, federation provider configuration and the synthetic OpenAI SDP/sideband test are available and validated. No Firebase, Vercel, OpenAI, Cloud Run, Apple or Google Play resources or credentials have been created. The owner explicitly authorized local implementation of dependent features while these external/device checks remain deferred; do not interpret that authorization as passing the release gates. CI is validation-only, uses pinned action revisions and no production secrets; it has not been run on GitHub.


## Local implementation continuation (17 September 2026)

The account gate uses Firebase Auth and an authenticated API; it does not fabricate a local user. Start Firebase Auth/Firestore/Storage emulators with project `demo-wellbeing`, then run `scripts/start-local-api.ps1`. Run Flutter with `--dart-define=USE_FIREBASE_EMULATORS=true`; Android emulator clients use host `10.0.2.2`. Emulator HTTP is enabled in the debug manifest only. Public production Firebase configuration placeholders are in `apps/mobile/config/production.example.json`; permanent OpenAI credentials stay server-side.

Implemented vertical-slice components include strict schemas for 15 resource types, revision/idempotency enforcement, owner-scoped references and signed cursors, encrypted projection/outbox transactions, snapshot/replay recovery, manual tracking forms/history, goals/habits/schedules/reminder definitions, dashboard, and deterministic progress. Reminder recurrence is a pure tested planner; OS delivery and server dispatch are not yet connected. AI context/memory validation and a server-only Responses adapter are implemented and unit tested; live coaching is not connected to HTTP/UI and realtime voice remains pending. The adapter uses structured output, store:false, a 1,500-token output cap and no automatic billed retries; it requires an explicitly configured evaluated model. See the [official structured output guide](https://developers.openai.com/api/docs/guides/structured-outputs). New feature strings still require localization completion.

Verification added: sixteen Node domain/provider/HTTP tests; three Firebase emulator suites covering deny-all client rules and server tenant isolation, receipts/conflicts/foreign references; seventeen Flutter unit/widget tests covering encrypted persistence, accessibility, deterministic analytics, DST/quiet hours and durable outbox retries/conflicts. Android debug build passes with notification-plugin desugaring enabled. These checks do not certify all roadmap acceptance criteria.

Server erasure deliberately fails closed with `ERASURE_PIPELINE_UNAVAILABLE` until the documented independent recovery manifest, dependent-artifact cleanup and acknowledgement pipeline are implemented. The client preserves queued deletions and displays their pending status. Do not report these as completed erasures. Account export/deletion, consent-invalidation worker execution, operational jobs, notification delivery, AI/memory/voice, imports and full production hardening remain implementation work; external account provisioning and macOS validation remain deferred.

A repeatable Android/Auth/API smoke harness is in `scripts/run-local-e2e.ps1`, with a synthetic-only fixture in `scripts/seed-local-e2e.mjs`. Invoke it through Firebase `emulators:exec` with Auth and Firestore on the documented loopback ports. The harness starts/stops its own local API process and uses no real credentials. The Android emulator smoke test passed: verified sign-in, account API loading, dashboard and hydration entry, followed by sign-out. This is one tested flow, not coverage of every feature.


## Account-preferences milestone

Implemented editable preferred name, IANA timezone and coaching tone; theme/reduced-motion controls; hidden summary metrics; persisted reminder preferences and quiet hours; explicit optional-consent controls; and sign-out with an unsynced-data warning. Preference edits require server confirmation. Ambiguous failures retain the same request ID/body for retry; revision conflicts require refresh/review. Account preferences are encrypted locally and refreshed through the synchronization feed. Revoking AI also revokes memory and atomically advances the data epoch, records consent events and persists a consent-invalidation job. Revocation bypasses an export barrier; granting consent does not. Jobs are durable intents; their worker/controller integration is a later milestone, and live AI/voice remain disabled.

The expanded Android test passed sign-in, hydration entry, profile editing, AI/memory grants, AI revocation with memory switched off, and sign-out. Flutter tests cover immutable preference retries, 200% text layout and hidden progress metrics. Emulator tests cover concurrent identical requests, conflicting revisions, strict field rejection, sync delivery and revocation during export. This is a completed local feature slice; P2 as a whole remains incomplete until privacy export/erasure and the documented security/device gates pass.

Next engineering milestone: durable privacy jobs and the independent deletion-recovery ledger, followed by export/erasure workers and their failure/recovery tests. Cloud provisioning and iOS execution remain isolated external release gates, not reasons to stop local implementation.
