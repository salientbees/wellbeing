import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getStorage } from 'firebase-admin/storage';
import { StorageRecoveryJournal } from '../../services/api/src/privacy/recovery_journal.ts';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { UserRepository } from '../../services/api/src/modules/repository.ts';
import { JobQueue } from '../../services/api/src/jobs/queue.ts';
import { requestRecordErasure } from '../../services/api/src/privacy/record_erasure.ts';
import { serializeManifest } from '../../packages/backend-domain/src/privacy.ts';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Firestore emulator required');
const app = initializeApp({ projectId: 'demo-wellbeing' }, `privacy-${randomUUID()}`);
const db = getFirestore(app);
after(async () => { await db.terminate(); await deleteApp(app); });

test('job leases fence concurrent workers, reclaim expiry and bound retries', async () => {
  let clock = Date.now();
  const queue = new JobQueue(db, () => new Date(clock)), id = randomUUID();
  await db.collection('jobs').doc(id).set({ ownerUid: 'synthetic', type: 'fixture', payload: {}, status: 'pending',
    attempt: 0, nextAttemptAt: Timestamp.fromMillis(clock), expiresAt: Timestamp.fromMillis(clock + 3600000) });
  const leases = await Promise.all([queue.claim(id), queue.claim(id)]);
  assert.equal(leases.filter(Boolean).length, 1);
  const first = leases.find(Boolean);
  clock += 61000;
  const second = await queue.claim(id);
  assert.ok(second);
  assert.equal(await queue.finish(first, 'completed'), false);
  assert.equal(await queue.finish(second, 'retryDue'), true);
  assert.equal(await queue.claim(id), null);
  for (let attempt = 3; attempt <= 5; attempt++) {
    clock += 300000;
    const lease = await queue.claim(id);
    assert.equal(lease.attempt, attempt);
    assert.equal(await queue.finish(lease, 'retryDue'), true);
  }
  assert.equal((await db.collection('jobs').doc(id).get()).data().status, 'failed');
  assert.equal(await queue.claim(id), null);
  assert.equal((await queue.due()).includes(id), false);
});

test('erasure acceptance waits for independent recovery acknowledgement and survives retry', async () => {
  const uid = `privacy-${randomUUID()}`, now = new Date();
  const repo = new UserRepository(db, { uid, authTime: now.getTime() / 1000 }, 'cursor-test', () => now);
  await repo.bootstrap({ profile: { preferredName: '', locale: 'en', timeZone: 'Etc/UTC', unitPreferences: { weight: 'kg', length: 'cm', volume: 'ml' }, coachingTone: 'gentle', ageEligible: true },
    consents: { aiProcessing: false, memory: false, analytics: false, crashReports: false, healthImport: false }, policyVersion: 'test' });
  await repo.mutate({ operationId: randomUUID(), operationCreatedAt: now.toISOString(), entityType: 'weight-logs', entityId: 'one', action: 'create', baseRevision: 0,
    payload: { occurredAt: now.toISOString(), localDate: now.toISOString().slice(0, 10), timeZone: 'Etc/UTC', utcOffsetMinutes: 0, source: 'manual', weightKg: 77.123 } });
  const request = { operationId: randomUUID(), scope: 'records', records: [{ entityType: 'weight-logs', entityId: 'one' }] };
  const policy = { hmacKey: 'synthetic-recovery-key-at-least-32-characters', keyVersion: 'test-v1', suppressionDays: 35 };
  const copies = new Map(); let unavailable = true;
  const journal = { async persist(manifest) {
    const content = serializeManifest(manifest);
    if (copies.has(manifest.jobId)) assert.equal(copies.get(manifest.jobId), content);
    copies.set(manifest.jobId, content);
    if (unavailable) throw new Error('Simulated lost acknowledgement');
  } };
  await assert.rejects(requestRecordErasure(repo, request, journal, policy), { code: 'RECOVERY_JOURNAL_UNAVAILABLE' });
  await assert.rejects(repo.list('weight-logs'), { code: 'PRIVACY_ERASURE_IN_PROGRESS' });
  assert.equal((await repo.root.collection('privacyExclusions').get()).size, 1);
  unavailable = false;
  const accepted = await requestRecordErasure(repo, request, journal, policy);
  assert.equal(accepted.recoveryAcknowledged, true);
  assert.equal(copies.size, 1);
  const ledger = (await db.collection('deletionLedger').doc(accepted.jobId).get()).data();
  assert.equal(ledger.recoveryAcknowledged, true);
  assert.equal(ledger.manifest.cutoffSeq, 1);
  assert.equal(JSON.stringify(ledger).includes(uid), false);
  assert.equal(JSON.stringify(ledger).includes('77.123'), false);
  assert.equal((await db.collection('privacyJobs').doc(accepted.jobId).get()).data().state, 'pending');
  assert.equal((await repo.account()).dataEpoch, 2);
  await requestRecordErasure(repo, request, journal, policy);
  assert.equal((await repo.account()).dataEpoch, 2);
  await assert.rejects(requestRecordErasure(repo, { ...request, records: [{ entityType: 'weight-logs', entityId: 'other' }] }, journal, policy), { code: 'IDEMPOTENCY_CONFLICT' });
});


test('Storage recovery manifests are immutable and idempotent outside Firestore', async () => {
  if (!process.env.FIREBASE_STORAGE_EMULATOR_HOST) throw new Error('Storage emulator required');
  const journal = new StorageRecoveryJournal(getStorage(app), 'demo-wellbeing-recovery.appspot.com');
  const manifest = { schemaVersion: 1, jobId: randomUUID(), ownerHash: 'a'.repeat(64), keyVersion: 'fixture',
    scope: 'records', records: [{ entityType: 'weight-logs', entityId: 'fixture' }], cutoffSeq: 10,
    deletedAt: '2026-09-18T00:00:00Z', suppressionExpiresAt: '2026-10-23T00:00:00Z' };
  await journal.persist(manifest);
  await journal.persist(manifest);
  await assert.rejects(journal.persist({ ...manifest, cutoffSeq: 11 }), /RECOVERY_MANIFEST_MISMATCH/);
  await journal.persist(manifest);
});
