import type { Storage } from 'firebase-admin/storage';
import { serializeManifest, type RecoveryJournal, type RecoveryManifest } from '../../../../packages/backend-domain/src/privacy.ts';

/** Storage is outside Firestore's rollback boundary. Bucket IAM/retention and
 * recovery completeness must be verified before enabling production erasure. */
export class StorageRecoveryJournal implements RecoveryJournal {
  private readonly storage: Storage;
  private readonly bucketName: string;
  constructor(storage: Storage, bucketName: string) {
    if (!bucketName) throw new Error('Recovery bucket is required');
    this.storage = storage; this.bucketName = bucketName;
  }
  async persist(manifest: RecoveryManifest): Promise<void> {
    const content = serializeManifest(manifest);
    const file = this.storage.bucket(this.bucketName).file(`deletion-ledger/v1/${manifest.ownerHash}/${manifest.jobId}.json`);
    try {
      const [existing] = await file.download();
      if (existing.toString('utf8') !== content) throw new Error('RECOVERY_MANIFEST_MISMATCH');
      return;
    } catch (error) {
      if ((error as { code?: number }).code !== 404) throw error;
    }
    try {
      await file.save(content, { resumable: false, contentType: 'application/json',
        metadata: { cacheControl: 'no-store' }, preconditionOpts: { ifGenerationMatch: 0 } });
    } catch (error) {
      // A completed previous attempt may have lost its acknowledgement.
      if ((error as { code?: number }).code !== 412) throw error;
    }
    // Verify both newly created and previously existing manifests. Never replace
    // an existing object, even if a Firestore rollback proposes different scope.
    const [stored] = await file.download();
    if (stored.toString('utf8') !== content) throw new Error('RECOVERY_MANIFEST_MISMATCH');
  }
}
