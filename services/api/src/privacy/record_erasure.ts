import { createHash, randomUUID } from 'node:crypto';
import { Timestamp } from 'firebase-admin/firestore';
import { erasureRequest, ownerRecoveryHash, recoveryManifest, type RecoveryJournal } from '../../../../packages/backend-domain/src/privacy.ts';
import { collections } from '../../../../packages/backend-domain/src/resources.ts';
import { requireRecent } from '../platform/auth.ts';
import { ApiError } from '../platform/errors.ts';
import type { UserRepository } from '../modules/repository.ts';

export interface RecoveryPolicy { hmacKey: string; keyVersion: string; suppressionDays: number }

/** Admission only: an accepted job is pending, never a claim of completed erasure.
 * HTTP exposure awaits the dependent-artifact cleanup worker and reconciliation. */
export async function requestRecordErasure(repo: UserRepository, input: unknown, journal: RecoveryJournal, policy: RecoveryPolicy) {
  const request = erasureRequest.parse(input), now = repo.clock();
  requireRecent(repo.principal, now.getTime());
  if (!Number.isInteger(policy.suppressionDays) || policy.suppressionDays < 35 || policy.suppressionDays > 365) throw new Error('Configure a verified recovery suppression period');
  const records = [...request.records].sort((a, b) => `${a.entityType}/${a.entityId}`.localeCompare(`${b.entityType}/${b.entityId}`));
  const hash = createHash('sha256').update(JSON.stringify({ scope: request.scope, records })).digest('hex');
  const ownerHash = ownerRecoveryHash(repo.principal.uid, policy.hmacKey), jobId = randomUUID();
  const receiptRef = repo.root.collection('operationReceipts').doc(request.operationId);
  const manifest = await repo.db.runTransaction(async tx => {
    const [account, receipt, sync] = await Promise.all([tx.get(repo.root), tx.get(receiptRef), tx.get(repo.root.collection('syncState').doc('main'))]);
    if (account.data()?.status !== 'active') throw new ApiError(403, 'ACCOUNT_DISABLED');
    if (receipt.exists) {
      if (receipt.data()?.requestHash !== hash || receipt.data()?.type !== 'recordErasure') throw new ApiError(409, 'IDEMPOTENCY_CONFLICT');
      const saved = await tx.get(repo.db.collection('deletionLedger').doc(receipt.data()!.jobId));
      if (!saved.exists) throw new ApiError(503, 'RECOVERY_LEDGER_INCOMPLETE');
      return recoveryManifest.parse(saved.data()!.manifest);
    }
    const sources = await tx.getAll(...records.map(r => repo.root.collection(collections[r.entityType]).doc(r.entityId)));
    if (sources.some(source => !source.exists || source.data()?.deletedAt)) throw new ApiError(404, 'NOT_FOUND');
    const value = recoveryManifest.parse({ schemaVersion: 1, jobId, ownerHash, keyVersion: policy.keyVersion,
      scope: 'records', records, cutoffSeq: sync.data()!.headSeq, deletedAt: now.toISOString(),
      suppressionExpiresAt: new Date(now.getTime() + policy.suppressionDays * 86400_000).toISOString() });
    const timestamp = Timestamp.fromDate(now), epoch = account.data()!.dataEpoch + 1;
    tx.create(repo.root.collection('privacyExclusions').doc(jobId), { scope: 'records', records, jobId, createdAt: timestamp });
    tx.create(repo.db.collection('privacyJobs').doc(jobId), { ownerUid: repo.principal.uid, type: 'eraseRange', state: 'awaitingRecovery', cutoffSeq: value.cutoffSeq, createdAt: timestamp, cursor: null });
    tx.create(repo.db.collection('deletionLedger').doc(jobId), { manifest: value, recoveryAcknowledged: false });
    tx.create(repo.db.collection('jobs').doc(jobId), { ownerUid: repo.principal.uid, type: 'recordErasure', payload: { privacyJobId: jobId },
      status: 'pending', nextAttemptAt: timestamp, attempt: 0, expiresAt: Timestamp.fromMillis(now.getTime() + 7 * 86400_000) });
    tx.create(receiptRef, { type: 'recordErasure', requestHash: hash, jobId, createdAt: timestamp });
    tx.update(repo.root, { dataEpoch: epoch });
    tx.update(repo.root.collection('syncState').doc('main'), { dataEpoch: epoch });
    return value;
  });
  try { await journal.persist(manifest); }
  catch { throw new ApiError(503, 'RECOVERY_JOURNAL_UNAVAILABLE'); }
  const state = await repo.db.runTransaction(async tx => {
    const ledgerRef = repo.db.collection('deletionLedger').doc(manifest.jobId);
    const ledger = await tx.get(ledgerRef);
    if (!ledger.exists) throw new ApiError(503, 'RECOVERY_LEDGER_INCOMPLETE');
    const jobRef = repo.db.collection('privacyJobs').doc(manifest.jobId);
    // Do not let an idempotent admission retry regress a completed worker state.
    const job = await tx.get(jobRef);
    if (!job.exists) throw new ApiError(503, 'RECOVERY_LEDGER_INCOMPLETE');
    tx.update(ledgerRef, { recoveryAcknowledged: true, acknowledgedAt: Timestamp.fromDate(repo.clock()) });
    if (job.data()?.state === 'awaitingRecovery') tx.update(jobRef, { state: 'pending' });
    return job.data()!.state === 'awaitingRecovery' ? 'pending' : job.data()!.state;
  });
  return { jobId: manifest.jobId, state, recoveryAcknowledged: true };
}
