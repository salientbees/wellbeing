import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { UserRepository } from '../../services/api/src/modules/repository.ts';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('This test requires the Firestore emulator');
const app = initializeApp({ projectId: 'demo-wellbeing' }, `repository-${randomUUID()}`);
const db = getFirestore(app);
after(async () => { await db.terminate(); await deleteApp(app); });
const setup = {
  profile: { preferredName: 'Synthetic', locale: 'en', timeZone: 'Etc/UTC', unitPreferences: { weight: 'kg', length: 'cm', volume: 'ml' }, coachingTone: 'gentle', ageEligible: true },
  consents: { aiProcessing: false, memory: false, analytics: false, crashReports: false, healthImport: false }, policyVersion: 'test',
};
test('tenant-owned mutation receipts, revision conflicts, foreign references and cursors', async () => {
  const uid = `test-${randomUUID()}`, otherUid = `test-${randomUUID()}`;
  const a = new UserRepository(db, { uid, authTime: Date.now() / 1000 }, 'test-only-shared-key');
  const b = new UserRepository(db, { uid: otherUid, authTime: Date.now() / 1000 }, 'test-only-shared-key');
  await a.bootstrap(setup); await b.bootstrap(setup);
  const op = { operationId: randomUUID(), entityType: 'weight-logs', entityId: 'weight-one', action: 'create', baseRevision: 0, operationCreatedAt: new Date().toISOString(), payload: { occurredAt: '2026-09-17T08:00:00Z', localDate: '2026-09-17', timeZone: 'Etc/UTC', utcOffsetMinutes: 0, source: 'manual', weightKg: 70 } };
  const result = await a.mutate(op);
  assert.equal(result.revision, 1);
  assert.deepEqual(await a.mutate(op), result);
  assert.equal((await a.changes()).changes.length, 1);
  assert.equal((await b.list('weight-logs')).entities.length, 0);
  await assert.rejects(a.mutate({ ...op, payload: { ...op.payload, weightKg: 71 } }), { code: 'IDEMPOTENCY_CONFLICT' });
  await assert.rejects(a.mutate({ ...op, operationId: randomUUID() }), { code: 'REVISION_CONFLICT' });
  await assert.rejects(b.changes((await a.changes()).nextCursor), { code: 'INVALID_CURSOR' });
  const receipt = (await a.root.collection('operationReceipts').doc(op.operationId).get()).data();
  assert.equal(JSON.stringify(receipt).includes('weightKg'), false);
  const schedule = { operationId: randomUUID(), entityType: 'schedules', entityId: 'schedule-one', action: 'create', baseRevision: 0, operationCreatedAt: new Date().toISOString(), payload: { kind: 'daily', localTime: '08:00', weekdays: [], startDate: '2026-09-17', timeZone: 'Etc/UTC', zoneMode: 'fixed', status: 'active', skipDates: [] } };
  await a.mutate(schedule);
  await assert.rejects(b.mutate({ ...schedule, operationId: randomUUID(), entityType: 'habits', entityId: 'habit-one', payload: { name: 'Synthetic habit', targetQuantity: 1, unit: 'count', scheduleId: 'schedule-one', status: 'active', effectiveFrom: '2026-09-17' } }), { code: 'NOT_FOUND' });
  // Fail closed until the independent erasure pipeline exists; never issue a false receipt.
  await assert.rejects(a.mutate({ ...op, operationId: randomUUID(), action: 'delete', baseRevision: 1, payload: {} }), { code: 'ERASURE_PIPELINE_UNAVAILABLE' });
  assert.equal((await a.list('weight-logs')).entities.length, 1);
});
