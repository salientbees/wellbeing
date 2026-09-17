import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { UserRepository } from '../../services/api/src/modules/repository.ts';
import { updatePreferences } from '../../services/api/src/modules/account_preferences.ts';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Emulator required');
const app = initializeApp({ projectId: 'demo-wellbeing' }, `preferences-${randomUUID()}`);
const db = getFirestore(app);
after(async () => { await db.terminate(); await deleteApp(app); });
test('preferences are revision-safe, idempotent, isolated and delivered through sync', async () => {
  const repo = new UserRepository(db, { uid: `test-${randomUUID()}`, authTime: Date.now() / 1000 }, 'fixture-key');
  await repo.bootstrap({
    profile: { preferredName: 'Before', locale: 'en', timeZone: 'Etc/UTC', unitPreferences: { weight: 'kg', length: 'cm', volume: 'ml' }, coachingTone: 'gentle', ageEligible: true },
    consents: { aiProcessing: false, memory: false, analytics: false, crashReports: false, healthImport: false }, policyVersion: 'test',
  });
  const patch = { operationId: randomUUID(), operationCreatedAt: new Date().toISOString(), baseRevision: 1, changes: { preferredName: 'After' } };
  const [first, retry] = await Promise.all([updatePreferences(repo, 'profile', patch), updatePreferences(repo, 'profile', patch)]);
  assert.equal(first.revision, 2); assert.equal(retry.revision, 2);
  assert.equal((await repo.account()).profile.preferredName, 'After');
  assert.equal((await repo.account()).profile.timeZone, 'Etc/UTC');
  await assert.rejects(updatePreferences(repo, 'profile', { ...patch, operationId: randomUUID() }), { code: 'REVISION_CONFLICT' });
  await assert.rejects(updatePreferences(repo, 'profile', { ...patch, changes: { preferredName: 'Different' } }), { code: 'IDEMPOTENCY_CONFLICT' });
  await assert.rejects(updatePreferences(repo, 'settings', { ...patch, changes: { aiProcessing: true } }));
  const feed = await repo.changes();
  assert.equal(feed.changes.length, 1);
  assert.equal(feed.changes[0].entity, null);
  assert.equal(feed.account.profile.preferredName, 'After');
  const consent = (category, granted, revision) => ({ operationId: randomUUID(), operationCreatedAt: new Date().toISOString(), baseRevision: revision, category, granted, policyVersion: 'test' });
  await assert.rejects(updatePreferences(repo, 'consents', consent('memory', true, 1)), { code: 'AI_CONSENT_REQUIRED' });
  await updatePreferences(repo, 'consents', consent('aiProcessing', true, 1));
  await updatePreferences(repo, 'consents', consent('memory', true, 2));
  await repo.root.collection('exportState').doc('main').set({ barrierExpiresAt: Timestamp.fromMillis(Date.now() + 60000) });
  const revoke = consent('aiProcessing', false, 3);
  const revoked = await updatePreferences(repo, 'consents', revoke);
  assert.equal(revoked.account.consents.aiProcessing, false);
  assert.equal(revoked.account.consents.memory, false);
  assert.equal(revoked.account.dataEpoch, 4);
  assert.equal((await repo.root.collection('jobs').get()).size, 3);
  await updatePreferences(repo, 'consents', revoke);
  assert.equal((await repo.root.collection('jobs').get()).size, 3);
  const snapshot = await repo.snapshot();
  assert.equal(snapshot.startSeq, 4);
});
