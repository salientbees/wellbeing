import { randomUUID } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { z } from 'zod';
import { resourceNames, mutation, type Resource } from '../../../packages/backend-domain/src/resources.ts';
import { authenticate } from './platform/auth.ts';
import { serverConfig } from './platform/config.ts';
import { firebase } from './platform/firebase.ts';
import { ApiError } from './platform/errors.ts';
import { UserRepository } from './modules/repository.ts';
import { updatePreferences } from './modules/account_preferences.ts';

async function readJson(request: IncomingMessage, limit: number) {
  if (!(request.headers['content-type'] ?? '').startsWith('application/json')) throw new ApiError(415, 'UNSUPPORTED_MEDIA_TYPE');
  const preParsed = (request as IncomingMessage & { body?: unknown }).body;
  if (preParsed !== undefined) {
    if (Buffer.byteLength(JSON.stringify(preParsed)) > limit) throw new ApiError(413, 'PAYLOAD_TOO_LARGE');
    return preParsed;
  }
  const chunks: Buffer[] = []; let length = 0;
  for await (const raw of request) { const chunk = Buffer.from(raw); length += chunk.length; if (length > limit) throw new ApiError(413, 'PAYLOAD_TOO_LARGE'); chunks.push(chunk); }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw new ApiError(400, 'MALFORMED_REQUEST'); }
}
export default async function handler(request: IncomingMessage, response: ServerResponse) {
  const requestId = randomUUID();
  response.setHeader('Cache-Control', 'private, no-store'); response.setHeader('Content-Type', 'application/json; charset=utf-8'); response.setHeader('X-Content-Type-Options', 'nosniff');
  try {
    const config = serverConfig(); const platform = firebase(config);
    const principal = await authenticate(request.headers, platform.auth, platform.attestation, config.emulator);
    const repository = new UserRepository(platform.db, principal, config.cursorKey);
    const url = new URL(request.url ?? '/', 'http://localhost');
    const path = url.pathname.replace(/^\/api/, ''); const method = request.method ?? 'GET';
    let result: unknown;
    if (path === '/v1/me/bootstrap' && method === 'POST') {
      await repository.quota('mutation'); result = await repository.bootstrap(await readJson(request, 65536));
    } else if (path === '/v1/me' && method === 'GET') {
      await repository.quota('read'); result = await repository.account();
    } else if ((method === 'PATCH' && ['/v1/me/profile', '/v1/me/settings'].includes(path)) || (method === 'POST' && path === '/v1/me/consents')) {
      await repository.quota('mutation');
      result = await updatePreferences(repository, path.split('/').at(-1) as 'profile' | 'settings' | 'consents', await readJson(request, 65536));
    } else if (path === '/v1/me/sync/mutations' && method === 'POST') {
      const input = z.strictObject({ operations: z.array(mutation).min(1).max(50) }).parse(await readJson(request, 262144));
      await repository.quota('mutation', input.operations.length);
      const results = [];
      for (const operation of input.operations) {
        try { results.push({ operationId: operation.operationId, status: 'success', ...await repository.mutate(operation) }); }
        catch (error) {
          if (!(error instanceof ApiError) && !(error instanceof z.ZodError)) throw error;
          results.push({ operationId: operation.operationId, status: 'error', code: error instanceof ApiError ? error.code : 'VALIDATION_FAILED', ...(error instanceof ApiError ? error.details : {}) });
        }
      }
      result = { results };
    } else if (path === '/v1/me/sync/snapshot' && method === 'GET') {
      await repository.quota('read'); result = await repository.snapshot(url.searchParams.get('cursor') ?? undefined);
    } else if (path === '/v1/me/sync/changes' && method === 'GET') {
      await repository.quota('read'); result = await repository.changes(url.searchParams.get('cursor') ?? undefined);
    } else {
      const match = /^\/v1\/me\/([a-z-]+)$/.exec(path);
      if (method !== 'GET' || !match || !resourceNames.includes(match[1] as Resource)) throw new ApiError(404, 'NOT_FOUND');
      await repository.quota('read'); result = await repository.list(match[1] as Resource, url.searchParams.get('cursor') ?? undefined);
    }
    response.statusCode = 200; response.end(JSON.stringify({ data: result, meta: { requestId, serverTime: new Date().toISOString() } }));
  } catch (error) {
    const apiError = error instanceof ApiError ? error : error instanceof z.ZodError ? new ApiError(422, 'VALIDATION_FAILED') : new ApiError(503, 'DEPENDENCY_UNAVAILABLE');
    response.statusCode = apiError.status;
    if (apiError.status === 429) response.setHeader('Retry-After', '60');
    response.end(JSON.stringify({ error: { code: apiError.code, message: apiError.code.replaceAll('_', ' ').toLowerCase(), requestId, retryable: apiError.status >= 500 || apiError.status === 429 } }));
  }
}
