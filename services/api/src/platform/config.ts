export interface ServerConfig { projectId: string; emulator: boolean; cursorKey: string; openaiKey?: string; textModel?: string }
export function serverConfig(env: NodeJS.ProcessEnv = process.env): ServerConfig {
  const emulator = env.APP_ENV === 'local';
  const projectId = env.FIREBASE_PROJECT_ID ?? '';
  if (!projectId || (emulator && !projectId.startsWith('demo-'))) throw new Error('Configure an explicit Firebase project; local mode requires demo-.');
  if (!emulator && Object.keys(env).some(key => /EMULATOR_HOST$/.test(key) && env[key])) throw new Error('Emulator endpoints are forbidden outside local mode.');
  if (emulator && (!env.FIREBASE_AUTH_EMULATOR_HOST || !env.FIRESTORE_EMULATOR_HOST)) throw new Error('Local mode requires both Auth and Firestore emulators.');
  if (!emulator && (!env.CURSOR_HMAC_KEY || env.CURSOR_HMAC_KEY.length < 32)) throw new Error('Configure CURSOR_HMAC_KEY with at least 32 characters.');
  return { projectId, emulator, cursorKey: env.CURSOR_HMAC_KEY ?? 'local-emulator-only-not-a-production-secret', ...(env.OPENAI_API_KEY ? { openaiKey: env.OPENAI_API_KEY } : {}), ...(env.OPENAI_TEXT_MODEL ? { textModel: env.OPENAI_TEXT_MODEL } : {}) };
}
