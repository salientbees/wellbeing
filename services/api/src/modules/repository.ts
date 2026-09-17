import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { FieldPath, Timestamp, type Firestore, type DocumentData } from 'firebase-admin/firestore';
import { bootstrap, collections, resourceNames, validateMutation, type Resource, type Entity } from '../../../../packages/backend-domain/src/resources.ts';
import { operationWindow } from '../../../../packages/backend-domain/src/contracts.ts';
import type { Principal } from '../platform/auth.ts';
import { ApiError } from '../platform/errors.ts';

const lifetime = 30 * 86400_000;
const canonical = (value: unknown): string => JSON.stringify(value, (_key, item: unknown) => item && typeof item === 'object' && !Array.isArray(item) ? Object.fromEntries(Object.entries(item).sort(([a], [b]) => a.localeCompare(b))) : item);
export const wire = (value: unknown): unknown => value instanceof Timestamp ? value.toDate().toISOString() : Array.isArray(value) ? value.map(wire) : value && typeof value === 'object' ? Object.fromEntries(Object.entries(value).map(([key, item]) => [key, wire(item)])) : value;
function entity(data: DocumentData, kind: Resource): Entity {
  const { id, revision, schemaVersion, createdAt, updatedAt, deletedAt, ...payload } = wire(data) as Record<string, any>;
  return { id, entityType: kind, revision, schemaVersion, createdAt, updatedAt, deletedAt: deletedAt ?? null, payload };
}
function persisted(payload: Record<string, unknown>) {
  return Object.fromEntries(Object.entries(payload).map(([key, value]) => [key, ['occurredAt', 'startAt', 'endAt'].includes(key) && typeof value === 'string' ? Timestamp.fromDate(new Date(value)) : value]));
}
export class UserRepository {
  readonly root;
  readonly db: Firestore; readonly principal: Principal; readonly cursorKey: string; readonly clock: () => Date;
  constructor(db: Firestore, principal: Principal, cursorKey: string, clock = () => new Date()) {
    this.db = db; this.principal = principal; this.cursorKey = cursorKey; this.clock = clock;
    if (!principal.uid || principal.uid.includes('/')) throw new ApiError(401, 'AUTH_REQUIRED');
    this.root = db.collection('users').doc(principal.uid);
  }
  async account() {
    return this.db.runTransaction(async tx => {
      const [root, profile, settings] = await tx.getAll(this.root, this.root.collection('profiles').doc('main'), this.root.collection('settings').doc('main'));
      const data = root!.data();
      if (!data) throw new ApiError(404, 'ONBOARDING_REQUIRED');
      if (data.status !== 'active') throw new ApiError(403, 'ACCOUNT_DISABLED');
      return { ...wire(data) as object, profile: wire(profile!.data()), settings: wire(settings!.data()) };
    });
  }

  async bootstrap(input: unknown) {
    const value = bootstrap.parse(input); const now = Timestamp.fromDate(this.clock());
    await this.db.runTransaction(async tx => {
      const current = await tx.get(this.root);
      if (current.exists) { if (current.data()?.status !== 'active') throw new ApiError(403, 'ACCOUNT_DISABLED'); return; }
      tx.create(this.root, { status: 'active', onboardingVersion: 1, consentVersion: 1, dataEpoch: 0, consents: value.consents, createdAt: now });
      const meta = { revision: 1, schemaVersion: 1, createdAt: now, updatedAt: now };
      tx.create(this.root.collection('profiles').doc('main'), { ...value.profile, ...meta });
      tx.create(this.root.collection('settings').doc('main'), { theme: 'system', reduceMotion: false, hiddenMetrics: [], weekStartsOn: 1, notificationPreferences: { enabled: false, quietStart: '22:00', quietEnd: '08:00' }, ...meta });
      tx.create(this.root.collection('syncState').doc('main'), { headSeq: 0, minimumAvailableSeq: 0, dataEpoch: 0 });
      for (const [category, granted] of Object.entries(value.consents)) tx.create(this.root.collection('consents').doc(), { category, granted, policyVersion: value.policyVersion, method: 'onboarding', recordedAt: now });
    });
    return this.account();
  }
  async quota(kind: 'read' | 'mutation', amount = 1) {
    const minute = Math.floor(this.clock().getTime() / 60_000); const ref = this.root.collection('usageBuckets').doc(`${kind}-${minute}`);
    await this.db.runTransaction(async tx => {
      const data = await tx.get(ref); const count = (data.data()?.count ?? 0) + amount;
      if (count > (kind === 'read' ? 120 : 60)) throw new ApiError(429, 'RATE_LIMITED');
      tx.set(ref, { count, expiresAt: Timestamp.fromMillis((minute + 2) * 60_000) });
    });
  }
  async mutate(input: unknown) {
    const op = validateMutation(input);
    // Erasure must not be acknowledged until the independent recovery manifest
    // and dependent-artifact worker are implemented and configured. Keep the
    // immutable client operation queued instead of falsely claiming erasure.
    if (op.action === 'delete') throw new ApiError(503, 'ERASURE_PIPELINE_UNAVAILABLE');
    const nowDate = this.clock(); const window = operationWindow(op.operationCreatedAt, nowDate);
    if (window !== 'valid') throw new ApiError(window === 'expired' ? 409 : 422, window === 'expired' ? 'RECONCILIATION_REQUIRED' : 'VALIDATION_FAILED');
    const hash = createHash('sha256').update(canonical(op)).digest('hex');
    const record = this.root.collection(collections[op.entityType]).doc(op.entityId);
    const receipt = this.root.collection('operationReceipts').doc(op.operationId); const state = this.root.collection('syncState').doc('main');
    return this.db.runTransaction(async tx => {
      const [account, previous, current, sync, barrier, exclusions] = await Promise.all([tx.get(this.root), tx.get(receipt), tx.get(record), tx.get(state), tx.get(this.root.collection('exportState').doc('main')), tx.get(this.root.collection('privacyExclusions').limit(1))]);
      if (account.data()?.status !== 'active') throw new ApiError(403, 'ACCOUNT_DISABLED');
      // Conservatively block writes while any selective erasure is active.
      if (!exclusions.empty) throw new ApiError(423, 'PRIVACY_ERASURE_IN_PROGRESS');
      if (previous.exists) {
        if (previous.data()?.requestHash !== hash) throw new ApiError(409, 'IDEMPOTENCY_CONFLICT');
        return previous.data()!.result;
      }
      if (barrier.data()?.barrierExpiresAt?.toMillis() > nowDate.getTime() && op.action !== 'delete') throw new ApiError(423, 'EXPORT_SNAPSHOT_BUSY');
      const old = current.data();
      if (old?.deletedAt) throw new ApiError(409, 'RECONCILIATION_REQUIRED');
      if ((old?.revision ?? 0) !== op.baseRevision || (op.action === 'create') === current.exists) throw new ApiError(409, 'REVISION_CONFLICT', { current: old ? entity(old, op.entityType) : null });
      const refs: Array<[Resource, string]> = [];
      if (typeof op.payload.scheduleId === 'string') refs.push(['schedules', op.payload.scheduleId]);
      if (typeof op.payload.habitId === 'string') refs.push(['habits', op.payload.habitId]);
      if (op.entityType === 'reminders' && typeof op.payload.subjectId === 'string') {
        if (op.payload.subjectType === 'habit') refs.push(['habits', op.payload.subjectId]);
        if (op.payload.subjectType === 'goal') refs.push(['goals', op.payload.subjectId]);
      }
      if (op.entityType === 'daily-check-ins' && op.action !== 'delete') for (const link of op.payload.linkedLogIds as Array<{ entityType: Resource; entityId: string }>) refs.push([link.entityType, link.entityId]);
      for (const [kind, id] of refs) { const parent = await tx.get(this.root.collection(collections[kind]).doc(id)); if (!parent.exists || parent.data()?.deletedAt) throw new ApiError(404, 'NOT_FOUND'); }
      if (op.entityType === 'habit-logs' && op.action !== 'delete') {
        const expected = createHash('sha256').update(`${op.payload.habitId}:${op.payload.occurrenceId}`).digest('hex');
        if (op.entityId !== expected) throw new ApiError(422, 'INVALID_OCCURRENCE_ID');
      }
      const now = Timestamp.fromDate(nowDate); const seq = (sync.data()?.headSeq ?? 0) + 1;
      const revision = (old?.revision ?? 0) + 1;
      const data = { ...(op.action === 'delete' ? {} : persisted(op.payload)), id: op.entityId, revision, schemaVersion: 1, createdAt: old?.createdAt ?? now, updatedAt: now, deletedAt: op.action === 'delete' ? now : null };
      const result = { entityId: op.entityId, entityType: op.entityType, revision, committedSeq: seq };
      tx.set(record, data);
      tx.set(state, { headSeq: seq, minimumAvailableSeq: sync.data()?.minimumAvailableSeq ?? 0, dataEpoch: (account.data()?.dataEpoch ?? 0) + 1 });
      tx.update(this.root, { dataEpoch: (account.data()?.dataEpoch ?? 0) + 1 });
      tx.create(this.root.collection('changes').doc(String(seq).padStart(16, '0')), { seq, entityType: op.entityType, entityId: op.entityId, revision, operation: op.action === 'delete' ? 'delete' : 'upsert', changedAt: now, expiresAt: Timestamp.fromMillis(nowDate.getTime() + lifetime) });
      tx.create(receipt, { requestHash: hash, result, createdAt: now, expiresAt: Timestamp.fromMillis(nowDate.getTime() + lifetime) });
      for (const date of new Set([old?.localDate, op.payload.localDate].filter(value => typeof value === 'string'))) tx.set(this.root.collection('dirtyPeriods').doc(date), { period: date, requestedThroughSeq: seq, dataEpoch: (account.data()?.dataEpoch ?? 0) + 1, updatedAt: now });
      if (['goals', 'habits', 'schedules'].includes(op.entityType)) tx.create(this.root.collection(`${collections[op.entityType].slice(0, -1)}Revisions`).doc(`${op.entityId}_${revision}`), { parentId: op.entityId, effectiveFrom: now, definition: wire(data), revision });
      return result;
    });
  }
  sign(value: object) { const body = Buffer.from(JSON.stringify({ ...value, uid: this.principal.uid, expires: this.clock().getTime() + 3600_000 })).toString('base64url'); return `${body}.${createHmac('sha256', this.cursorKey).update(body).digest('base64url')}`; }
  cursor(token: string, kind: string): Record<string, any> {
    const [body, mac, extra] = token.split('.'); if (!body || !mac || extra !== undefined || token.length > 4096) throw new ApiError(400, 'INVALID_CURSOR');
    const expected = createHmac('sha256', this.cursorKey).update(body).digest(); const actual = Buffer.from(mac, 'base64url');
    if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) throw new ApiError(400, 'INVALID_CURSOR');
    let value; try { value = JSON.parse(Buffer.from(body, 'base64url').toString()); } catch { throw new ApiError(400, 'INVALID_CURSOR'); }
    if (value.uid !== this.principal.uid || value.kind !== kind) throw new ApiError(400, 'INVALID_CURSOR');
    if (value.expires < this.clock().getTime()) throw new ApiError(410, 'CURSOR_EXPIRED'); return value;
  }
  async list(kind: Resource, cursor?: string) {
    await this.account();
    const exclusions = await this.root.collection('privacyExclusions').limit(1).get(); if (!exclusions.empty) throw new ApiError(423, 'PRIVACY_ERASURE_IN_PROGRESS');
    const after = cursor ? this.cursor(cursor, kind).after as string : '';
    let query = this.root.collection(collections[kind]).orderBy(FieldPath.documentId()).limit(100); if (after) query = query.startAfter(after);
    const page = await query.get();
    return { entities: page.docs.filter(d => !d.data().deletedAt).map(d => entity(d.data(), kind)), nextCursor: page.size === 100 ? this.sign({ kind, after: page.docs.at(-1)!.id }) : null };
  }
  async changes(token?: string) {
    await this.account();
    if (!(await this.root.collection('privacyExclusions').limit(1).get()).empty) throw new ApiError(423, 'PRIVACY_ERASURE_IN_PROGRESS');
    const state = (await this.root.collection('syncState').doc('main').get()).data()!;
    const cursor = token ? this.cursor(token, 'changes') : { after: 0, head: state.headSeq };
    if (cursor.after < state.minimumAvailableSeq) throw new ApiError(410, 'CURSOR_EXPIRED');
    const head = cursor.after >= cursor.head ? state.headSeq : cursor.head;
    const docs = await this.root.collection('changes').orderBy('seq').startAfter(cursor.after).endAt(head).limit(100).get();
    const changes = await Promise.all(docs.docs.map(async doc => { const d = doc.data(); if (['profile', 'settings', 'consents'].includes(d.entityType)) return { ...wire(d) as object, entity: null }; const item = await this.root.collection(collections[d.entityType as Resource]).doc(d.entityId).get(); return { ...wire(d) as object, entity: item.exists ? entity(item.data()!, d.entityType) : null }; }));
    return { account: await this.account(), changes, headSeq: head, minimumAvailableSeq: state.minimumAvailableSeq, dataEpoch: state.dataEpoch, nextCursor: this.sign({ kind: 'changes', after: docs.docs.at(-1)?.data().seq ?? cursor.after, head }) };
  }
  async snapshot(token?: string) {
    await this.account();
    if (!(await this.root.collection('privacyExclusions').limit(1).get()).empty) throw new ApiError(423, 'PRIVACY_ERASURE_IN_PROGRESS');
    const state = (await this.root.collection('syncState').doc('main').get()).data()!;
    const cursor = token ? this.cursor(token, 'snapshot') : { index: 0, after: '', start: state.headSeq, startedAt: this.clock().getTime() };
    if (cursor.start < state.minimumAvailableSeq || this.clock().getTime() - cursor.startedAt > 3600_000) throw new ApiError(410, 'CURSOR_EXPIRED');
    const kind = resourceNames[cursor.index as number]; if (!kind) throw new ApiError(400, 'INVALID_CURSOR');
    let query = this.root.collection(collections[kind]).orderBy(FieldPath.documentId()).limit(100);
    if (cursor.after) query = query.startAfter(cursor.after);
    const page = await query.get(); const index = page.size === 100 ? cursor.index : cursor.index + 1;
    return { entities: page.docs.filter(d => !d.data().deletedAt).map(d => entity(d.data(), kind)), startSeq: cursor.start,
      nextCursor: index >= resourceNames.length ? null : this.sign({ kind:'snapshot', index, after:page.size === 100 ? page.docs.at(-1)!.id : '', start:cursor.start, startedAt:cursor.startedAt }),
      replayCursor: this.sign({ kind:'changes', after:cursor.start, head:cursor.start }),
    };
  }
}
