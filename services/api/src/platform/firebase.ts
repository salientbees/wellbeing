import { getApps, initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { getAppCheck } from 'firebase-admin/app-check';
import type { ServerConfig } from './config.ts';
export function firebase(config: ServerConfig) {
  const app = getApps().find(app => app.name === config.projectId) ?? initializeApp({ projectId: config.projectId, ...(config.emulator ? {} : { credential: applicationDefault() }) }, config.projectId);
  return { db: getFirestore(app), auth: getAuth(app), attestation: getAppCheck(app) };
}
