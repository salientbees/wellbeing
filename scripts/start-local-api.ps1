$ErrorActionPreference = 'Stop'
$env:APP_ENV = 'local'
$env:FIREBASE_PROJECT_ID = 'demo-wellbeing'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_STORAGE_EMULATOR_HOST = '127.0.0.1:9199'
node "$PSScriptRoot/../services/api/dev.ts"
