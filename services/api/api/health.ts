import { randomUUID } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';

/** Liveness only: intentionally does not claim cloud services are configured. */
export default function health(request: IncomingMessage, response: ServerResponse): void {
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  const requestId = randomUUID();
  if (request.method !== 'GET') {
    response.setHeader('Allow', 'GET');
    response.statusCode = 405;
    response.end(JSON.stringify({ error: { code: 'METHOD_NOT_ALLOWED', message: 'Use GET.', requestId, retryable: false } }));
    return;
  }
  response.statusCode = 200;
  response.end(JSON.stringify({ data: { status: 'alive' }, meta: { requestId, serverTime: new Date().toISOString() } }));
}
