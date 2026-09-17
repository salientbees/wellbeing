param([string]$Flutter = 'C:\development\flutter\bin\flutter.bat')
$ErrorActionPreference = 'Stop'
$env:APP_ENV = 'local'
$env:FIREBASE_PROJECT_ID = 'demo-wellbeing'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$repositoryPath = Split-Path -Parent $PSScriptRoot
node "$PSScriptRoot/seed-local-e2e.mjs"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$apiProcess = Start-Process -FilePath (Get-Command node).Source -ArgumentList @('services/api/dev.ts') -WorkingDirectory $repositoryPath -WindowStyle Hidden -PassThru
try {
    Push-Location "$repositoryPath/apps/mobile"
    & $Flutter test integration_test/account_tracking_test.dart -d emulator-5554 --dart-define=USE_FIREBASE_EMULATORS=true
    $testExitCode = $LASTEXITCODE
} finally {
    Pop-Location
    if (-not $apiProcess.HasExited) { Stop-Process -Id $apiProcess.Id }
}
exit $testExitCode
