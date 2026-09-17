import { createServer } from 'node:http';
import handler from './src/handler.ts';
import { serverConfig } from './src/platform/config.ts';
const config = serverConfig();
if (!config.emulator) throw new Error('The local server only runs with demo Firebase emulators.');
const server = createServer((req, res) => { void handler(req, res); });
server.requestTimeout = 30_000;
server.headersTimeout = 15_000;
server.listen(8787, '127.0.0.1', () => process.stdout.write('Wellbeing local API listening on 127.0.0.1:8787 (demo emulators only)\n'));
