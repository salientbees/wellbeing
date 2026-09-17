import { randomUUID } from 'node:crypto';
import { FieldValue, Timestamp, type Firestore } from 'firebase-admin/firestore';

export interface JobLease { id: string; token: string; ownerUid: string; type: string; payload: Record<string, unknown>; attempt: number }
/** Transactional lease fencing for the documented global jobs collection. */
export class JobQueue {
  readonly db: Firestore;
  readonly clock: () => Date;
  constructor(db: Firestore, clock = () => new Date()) { this.db = db; this.clock = clock; }
  async claim(id: string): Promise<JobLease | null> {
    if (!/^[A-Za-z0-9_-]{1,150}$/.test(id)) throw new Error('Invalid job identifier');
    return this.db.runTransaction(async tx => {
      const ref = this.db.collection('jobs').doc(id), snapshot = await tx.get(ref), job = snapshot.data();
      const now = this.clock().getTime();
      if (!job || !['pending', 'retryDue', 'leased'].includes(job.status) || job.nextAttemptAt?.toMillis() > now || job.leaseExpiresAt?.toMillis() > now) return null;
      if (job.expiresAt.toMillis() <= now || job.attempt >= 5) {
        tx.update(ref, { status: 'expired', nextAttemptAt: FieldValue.delete(), leaseToken: FieldValue.delete(), leaseExpiresAt: FieldValue.delete() });
        return null;
      }
      const token = randomUUID(), expires = Timestamp.fromMillis(now + 60_000);
      tx.update(ref, { status: 'leased', leaseToken: token, leaseExpiresAt: expires, nextAttemptAt: expires, attempt: job.attempt + 1 });
      return { id, token, ownerUid: job.ownerUid, type: job.type, payload: job.payload, attempt: job.attempt + 1 };
    });
  }
  async finish(lease: JobLease, outcome: 'completed' | 'retryDue' | 'failed'): Promise<boolean> {
    return this.db.runTransaction(async tx => {
      const ref = this.db.collection('jobs').doc(lease.id), job = (await tx.get(ref)).data();
      const now = this.clock().getTime();
      if (!job || job.status !== 'leased' || job.leaseToken !== lease.token || job.leaseExpiresAt.toMillis() <= now) return false;
      const retry = outcome === 'retryDue' && job.attempt < 5 && job.expiresAt.toMillis() > now;
      tx.update(ref, { status: retry ? 'retryDue' : outcome === 'retryDue' ? 'failed' : outcome,
        nextAttemptAt: retry ? Timestamp.fromMillis(now + Math.min(300_000, 1000 * 2 ** job.attempt * (0.5 + Math.random()))) : FieldValue.delete(),
        leaseToken: FieldValue.delete(), leaseExpiresAt: FieldValue.delete(), updatedAt: Timestamp.fromMillis(now) });
      return true;
    });
  }
  async due(limit = 20): Promise<string[]> {
    if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error('Invalid batch limit');
    const page = await this.db.collection('jobs').where('nextAttemptAt', '<=', Timestamp.fromDate(this.clock())).orderBy('nextAttemptAt').limit(limit).get();
    return page.docs.map(doc => doc.id);
  }
}
