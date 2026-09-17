import type { IncomingHttpHeaders } from 'node:http';
import type { Auth } from 'firebase-admin/auth';
import type { AppCheck } from 'firebase-admin/app-check';
import { ApiError } from './errors.ts';
export interface Principal { uid: string; authTime: number }
export async function authenticate(headers: IncomingHttpHeaders, auth: Auth, attestation: AppCheck, emulator: boolean): Promise<Principal> {
  const authorization = headers.authorization;
  if (!authorization?.startsWith('Bearer ') || authorization.length > 8192) throw new ApiError(401, 'AUTH_REQUIRED');
  let token;
  try { token = await auth.verifyIdToken(authorization.slice(7), true); } catch { throw new ApiError(401, 'AUTH_REQUIRED'); }
  if (!token.email_verified) throw new ApiError(403, 'EMAIL_VERIFICATION_REQUIRED');
  if (!emulator) {
    const appCheck = headers['x-firebase-appcheck'];
    if (typeof appCheck !== 'string') throw new ApiError(403, 'ATTESTATION_FAILED');
    try { await attestation.verifyToken(appCheck); } catch { throw new ApiError(403, 'ATTESTATION_FAILED'); }
  }
  return { uid: token.uid, authTime: token.auth_time };
}
export function requireRecent(principal: Principal, now = Date.now()) {
  const age = now / 1000 - principal.authTime;
  if (age < -300 || age > 300) throw new ApiError(401, 'REAUTHENTICATION_REQUIRED');
}
