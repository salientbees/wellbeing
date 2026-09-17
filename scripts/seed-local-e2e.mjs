import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { UserRepository } from '../services/api/src/modules/repository.ts';
if (process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099' || process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080') throw new Error('Expected local emulators');
const app = initializeApp({ projectId: 'demo-wellbeing' });
const uid = 'wellbeing-e2e-synthetic';
await getAuth(app).createUser({ uid, email: 'wellbeing-e2e@example.test', password: 'Synthetic-only-password-42', emailVerified: true });
await new UserRepository(getFirestore(app), { uid, authTime: Date.now() / 1000 }, 'local-test-only').bootstrap({
  profile: { preferredName: 'Emulator Test', locale: 'en', timeZone: 'Etc/UTC', unitPreferences: { weight: 'kg', length: 'cm', volume: 'ml' }, coachingTone: 'gentle', ageEligible: true },
  consents: { aiProcessing: false, memory: false, analytics: false, crashReports: false, healthImport: false }, policyVersion: 'test',
});
await getFirestore(app).terminate();
await deleteApp(app);
