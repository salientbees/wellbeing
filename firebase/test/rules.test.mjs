import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { initializeTestEnvironment, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, collection, getDocs, deleteDoc } from 'firebase/firestore';
import { ref, uploadString, getBytes, listAll, deleteObject } from 'firebase/storage';

test('all direct client data access is denied, including owners and nested paths', async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-wellbeing',
    firestore: { host: '127.0.0.1', port: 8080, rules: await readFile('firebase/firestore.rules', 'utf8') },
    storage: { host: '127.0.0.1', port: 9199, rules: await readFile('firebase/storage.rules', 'utf8') },
  });
  try {
    await env.withSecurityRulesDisabled(async context => {
      await setDoc(doc(context.firestore(), 'users/user-a/weightLogs/record'), { synthetic: true });
      await uploadString(ref(context.storage(), 'users/user-a/artifacts/report'), 'synthetic');
    });
    for (const context of [env.unauthenticatedContext(), env.authenticatedContext('user-a'), env.authenticatedContext('user-b')]) {
      const db = context.firestore();
      const record = doc(db, 'users/user-a/weightLogs/record');
      await assertFails(getDoc(record));
      await assertFails(setDoc(record, { synthetic: false }));
      await assertFails(deleteDoc(record));
      await assertFails(getDocs(collection(db, 'users')));
      const object = ref(context.storage(), 'users/user-a/artifacts/report');
      await assertFails(getBytes(object));
      await assertFails(uploadString(object, 'replacement'));
      await assertFails(deleteObject(object));
      await assertFails(listAll(ref(context.storage(), 'users/user-a/artifacts')));
    }
  } finally { await env.cleanup(); }
});
