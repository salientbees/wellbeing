import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { Storage } from 'firebase-admin/storage';
import { StorageRecoveryJournal } from '../src/privacy/recovery_journal.ts';
import type { RecoveryManifest } from '../../../packages/backend-domain/src/privacy.ts';

test('concurrent manifest writes require atomic generation preconditions and reject conflicting scope', async () => {
  let stored: string | undefined;
  let initialReads = 0;
  const file = {
    async download() {
      if (++initialReads <= 2 || stored === undefined) throw { code: 404 };
      return [Buffer.from(stored)];
    },
    async save(content: string, options: { preconditionOpts: { ifGenerationMatch: number } }) {
      assert.equal(options.preconditionOpts.ifGenerationMatch, 0);
      if (stored !== undefined) throw { code: 412 };
      stored = content;
    },
  };
  const storage = { bucket: () => ({ file: () => file }) } as unknown as Storage;
  const journal = new StorageRecoveryJournal(storage, 'fixture-bucket');
  const manifest: RecoveryManifest = { schemaVersion: 1, jobId: 'b9103272-32e9-440c-8b7b-4cfad829f905', ownerHash: 'a'.repeat(64),
    keyVersion: 'v1', scope: 'records', records: [{ entityType: 'weight-logs', entityId: 'one' }], cutoffSeq: 1,
    deletedAt: '2026-09-18T00:00:00Z', suppressionExpiresAt: '2026-10-23T00:00:00Z' };
  const results = await Promise.allSettled([journal.persist(manifest), journal.persist({ ...manifest, cutoffSeq: 2 })]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.filter(r => r.status === 'rejected').length, 1);
  assert.equal(JSON.parse(stored!).cutoffSeq, 1);
});
