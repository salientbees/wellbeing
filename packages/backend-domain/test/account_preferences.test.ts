import { test } from 'node:test';
import assert from 'node:assert/strict';
import { profilePatch, settingsPatch, consentChange } from '../src/account_preferences.ts';
const metadata = { operationId: 'b9103272-32e9-440c-8b7b-4cfad829f905', operationCreatedAt: '2026-09-17T08:00:00Z', baseRevision: 1 };
test('account patches reject server fields, eligibility rewriting and invalid time zones', () => {
  assert.equal(profilePatch.safeParse({ ...metadata, changes: { preferredName: 'Name' } }).success, true);
  for (const changes of [{ uid: 'other' }, { ageEligible: false }, { timeZone: 'not/a/zone' }, {}, { consentVersion: 12 }]) {
    assert.equal(profilePatch.safeParse({ ...metadata, changes }).success, false);
  }
});
test('settings cannot grant consent and quiet-hour values are validated', () => {
  for (const changes of [{ aiProcessing: true }, { notificationPreferences: { enabled: true, quietStart: '25:00', quietEnd: '07:00' } }]) {
    assert.equal(settingsPatch.safeParse({ ...metadata, changes }).success, false);
  }
  assert.equal(consentChange.safeParse({ ...metadata, category: 'memory', granted: false, policyVersion: 'test' }).success, true);
});
