// Standalone editor server: the built app (dist/) + the build API.
//   npm run serve            (vite build, then this; http://127.0.0.1:5180)
//   PORT=8080 HOST=0.0.0.0 node server/index.ts
// Listens on 127.0.0.1 by default: the API runs KickAssembler on request.

import { existsSync, readFileSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize } from 'node:path';
import { createApi } from './api.ts';
import { C64_ASSETS, DIST_DIR, MOD_SRC } from './paths.ts';

const PORT = Number(process.env.PORT ?? 5180);
const HOST = process.env.HOST ?? '127.0.0.1';
const TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.wasm': 'application/wasm',
  '.svg': 'image/svg+xml',
  '.json': 'application/json',
  '.png': 'image/png',
};

if (!existsSync(join(DIST_DIR, 'index.html'))) {
  console.error('dist/ not found: run "npm run build" first (or "npm run serve")');
  process.exit(1);
}

const api = createApi({ modDir: MOD_SRC });

createServer((req, res) => {
  api(req, res, () => {
    const path = decodeURIComponent(new URL(req.url ?? '/', 'http://x').pathname);
    const asset = path.startsWith('/c64/') ? C64_ASSETS[path.slice(5)] : undefined;
    let file = asset?.path ?? join(DIST_DIR, normalize(path).replace(/^(\.\.[/\\])+/, ''));
    if (!asset && (!existsSync(file) || statSync(file).isDirectory())) file = join(DIST_DIR, 'index.html');
    res.writeHead(200, { 'Content-Type': asset?.type ?? TYPES[extname(file)] ?? 'application/octet-stream' });
    res.end(readFileSync(file));
  });
}).listen(PORT, HOST, () => console.log(`Thrust level editor: http://${HOST}:${PORT}/`));
