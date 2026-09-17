import { createHash } from 'node:crypto';
import { Timestamp } from 'firebase-admin/firestore';
import { profilePatch, settingsPatch, consentChange } from '../../../../packages/backend-domain/src/account_preferences.ts';
import { profile, settings } from '../../../../packages/backend-domain/src/resources.ts';
import { operationWindow } from '../../../../packages/backend-domain/src/contracts.ts';
import { ApiError } from '../platform/errors.ts';
import type { UserRepository } from './repository.ts';

export async function updatePreferences(repository: UserRepository, kind: 'profile' | 'settings' | 'consents', input: unknown) {
  const value = kind === 'profile' ? profilePatch.parse(input) : kind === 'settings' ? settingsPatch.parse(input) : consentChange.parse(input);
  const now = repository.clock();
  const window = operationWindow(value.operationCreatedAt, now);
  if (window !== 'valid') throw new ApiError(409, 'RECONCILIATION_REQUIRED');
  const hash = createHash('sha256').update(JSON.stringify({ kind, value }, (_key, item) =>
    item && typeof item === 'object' && !Array.isArray(item) ? Object.fromEntries(Object.entries(item).sort(([a], [b]) => a.localeCompare(b))) : item)).digest('hex');
  const root = repository.root;
  const receipt = root.collection('operationReceipts').doc(value.operationId);
  const stateRef = root.collection('syncState').doc('main');
  const recordRef = kind === 'consents' ? root : root.collection(kind === 'profile' ? 'profiles' : 'settings').doc('main');
  const result = await repository.db.runTransaction(async tx => {
    const [account, record, previous, sync, exclusions, barrier] = await Promise.all([
      tx.get(root), tx.get(recordRef), tx.get(receipt), tx.get(stateRef),
      tx.get(root.collection('privacyExclusions').limit(1)), tx.get(root.collection('exportState').doc('main')),
    ]);
    const data = account.data();
    if (data?.status !== 'active') throw new ApiError(403, 'ACCOUNT_DISABLED');
    if (previous.exists) {
      if (previous.data()?.requestHash !== hash) throw new ApiError(409, 'IDEMPOTENCY_CONFLICT');
      return previous.data()!.result;
    }
    const revoking = 'granted' in value && !value.granted;
    if (!revoking && !exclusions.empty) throw new ApiError(423, 'PRIVACY_ERASURE_IN_PROGRESS');
    if (!revoking && barrier.data()?.barrierExpiresAt?.toMillis() > now.getTime()) throw new ApiError(423, 'EXPORT_SNAPSHOT_BUSY');
    const current = record.data();
    const revision = kind === 'consents' ? data.consentVersion : current?.revision;
    if (value.baseRevision !== revision) throw new ApiError(409, 'REVISION_CONFLICT');
    const timestamp = Timestamp.fromDate(now), seq = (sync.data()?.headSeq ?? 0) + 1;
    const epoch = data.dataEpoch + 1;
    if (kind === 'consents' && 'category' in value) {
      const choices = { ...data.consents, [value.category]: value.granted };
      if (value.category === 'memory' && value.granted && !choices.aiProcessing) throw new ApiError(422, 'AI_CONSENT_REQUIRED');
      if (!choices.aiProcessing) choices.memory = false;
      tx.update(root, { consents: choices, consentVersion: revision + 1, dataEpoch: epoch });
      for (const category of Object.keys(choices)) {
        if (choices[category] !== data.consents[category]) tx.create(root.collection('consents').doc(`${value.operationId}_${category}`), {
          category, granted: choices[category], policyVersion: value.policyVersion, method: 'settings', recordedAt: timestamp,
        });
      }
      // Durable invalidation intent; every future AI publisher/controller must
      // also read current consent/epoch, so worker lag cannot authorize output.
      tx.create(repository.db.collection('jobs').doc(`consent_${createHash('sha256').update(`${repository.principal.uid}:${value.operationId}`).digest('hex')}`), {
        ownerUid: repository.principal.uid, type: 'consentInvalidation', status: 'pending', payload: { targetEpoch: epoch },
        createdAt: timestamp, nextAttemptAt: timestamp, attempt: 0, expiresAt: Timestamp.fromMillis(now.getTime() + 7 * 86400_000),
      });
    } else if ('changes' in value) {
      const { revision: _revision, schemaVersion: _schema, createdAt: _created, updatedAt: _updated, ...existing } = current!;
      const merged = kind === 'profile' ? profile.parse({ ...existing, ...value.changes }) : settings.parse({ ...existing, ...value.changes });
      tx.set(recordRef, { ...merged, revision: revision + 1, schemaVersion: 1, createdAt: current!.createdAt, updatedAt: timestamp });
      tx.update(root, { dataEpoch: epoch });
    }
    tx.set(stateRef, { ...sync.data(), headSeq: seq, dataEpoch: epoch });
    tx.create(root.collection('changes').doc(String(seq).padStart(16, '0')), {
      seq, entityType: kind, entityId: 'main', revision: revision + 1,
      operation: 'upsert', changedAt: timestamp, expiresAt: Timestamp.fromMillis(now.getTime() + 30 * 86400_000),
    });
    const result = { revision: revision + 1, committedSeq: seq };
    tx.create(receipt, { requestHash: hash, result, createdAt: timestamp, expiresAt: Timestamp.fromMillis(now.getTime() + 30 * 86400_000) });
    return result;
  });
  return { ...result, account: await repository.account() };
}
