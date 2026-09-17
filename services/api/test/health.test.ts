import { createServer } from 'node:http';
import { once } from 'node:events';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import health from '../api/health.ts';
import { errorEnvelope, responseMeta } from '../../../packages/backend-domain/src/contracts.ts';

test('liveness is uncached and rejects mutations with the common safe error contract', async () => {
  const server = createServer(health);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const url = `http://127.0.0.1:${address.port}/health`;
    const response = await fetch(url);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    const body = await response.json();
    assert.deepEqual(body.data, { status: 'alive' });
    responseMeta.parse(body.meta);
    const rejected = await fetch(url, { method: 'POST' });
    assert.equal(rejected.status, 405);
    assert.equal(rejected.headers.get('allow'), 'GET');
    errorEnvelope.parse(await rejected.json());
  } finally {
    server.closeAllConnections();
    server.close();
    await once(server, 'close');
  }
});
