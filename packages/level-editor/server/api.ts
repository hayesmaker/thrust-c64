// Build API for the level editor (plain Node, no dependencies). Used as
// middleware by the Vite dev server (vite.config.ts) and by server/index.ts.
//
//   GET  /api/source              the mod's levels.asm + level_tables.asm (+ hash, memory layout)
//   GET  /api/template            the game file new games start from (the original levels)
//   POST /api/build               build a temp copy of the mod with the posted level files
//   GET  /api/builds/<id>/<file>  thrust.prg, play.prg, thrust.sym, thrust.vs, kickass.log
//
// The mod source is read-only: games are saved as JSON files by the browser.

import { execFile } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export interface ApiOptions {
  /** packages/thrusty-levels/src */
  modDir: string;
  /** game file new games start from (GET /api/template); none: from modDir's levels */
  template?: string;
  kickass?: string;
  /** the command that runs KickAssembler's jar: java, or a sandbox wrapper (deploy/kickass-sandbox.sh) */
  java?: string;
  buildsDir?: string;
  keepBuilds?: number;
  /** a build is killed after this long */
  timeoutMs?: number;
  /** builds waiting or running; more get 503 */
  maxQueue?: number;
}

export interface BuildError {
  file: string;
  line: number;
  column: number;
  message: string;
}

export interface BuildResult {
  id: string;
  ok: boolean;
  errors: BuildError[];
  log: string;
  ms: number;
  /** files available under /api/builds/<id>/ */
  files: string[];
  /** play.prg starts on this level (null: same as thrust.prg) */
  startLevel: number | null;
  prgBytes?: number;
}

const SOURCE_FILES = { levelsAsm: 'levels.asm', tablesAsm: 'level_tables.asm' } as const;
const BUILD_FILES = new Set(['thrust.prg', 'play.prg', 'thrust.sym', 'thrust.vs', 'kickass.log']);
const MAX_BODY = 4 * 1024 * 1024;

type Next = (err?: unknown) => void;

export function sourceHash(levelsAsm: string, tablesAsm: string): string {
  return createHash('sha1').update(levelsAsm).update('\0').update(tablesAsm).digest('hex').slice(0, 16);
}

/** KickAssembler reports "Error: <message>" then "at line N, column C in <file>".
 *  A failed .assert only prints "<name>=<value> (<expected>) -- ERROR IN ASSERTION!!!"
 *  and still writes the PRG, so those count as errors too. */
export function parseKickAssErrors(log: string): BuildError[] {
  const out: BuildError[] = [];
  const re = /Error: (.+)\r?\n\s*at line (\d+), column (\d+) in (\S+)/g;
  for (let m = re.exec(log); m; m = re.exec(log))
    out.push({ message: m[1].trim(), line: Number(m[2]), column: Number(m[3]), file: m[4] });
  const as = /^\s*(.+?)=\S* \(\S*\) -- ERROR IN ASSERTION!!!/gm;
  for (let m = as.exec(log); m; m = as.exec(log))
    out.push({ message: `assertion failed: ${m[1].trim()}`, line: 0, column: 0, file: 'thrust.asm' });
  return out;
}

/** Where the mod keeps its level data. thrusty-levels puts levels.asm in its
 *  own area (LEVELS_AREA_START/END in thrust.asm); otherwise it is in the
 *  main block like the original game. */
export interface Layout {
  levelsArea: { start: number; end: number } | null;
}

export function readLayout(thrustAsm: string): Layout {
  const c = (name: string) => {
    const m = new RegExp(`^\\.const\\s+${name}\\s*=\\s*\\$([0-9a-fA-F]+)`, 'm').exec(thrustAsm);
    return m ? parseInt(m[1], 16) : null;
  };
  const start = c('LEVELS_AREA_START');
  const end = c('LEVELS_AREA_END');
  return { levelsArea: start !== null && end !== null && end > start ? { start, end } : null };
}

/** Make a PRG start on `level`: a new game does `sta total_levels_played /
 *  lda #$ff / sta level_number` and start_new_level increments it, so the
 *  $FF becomes level - 1. Addresses come from the KickAssembler .sym file. */
export function patchStartLevel(prg: Uint8Array, sym: string, level: number): Uint8Array {
  const label = (name: string) => {
    const m = new RegExp(`\\.label\\s+${name}\\s*=\\s*\\$([0-9a-fA-F]+)`).exec(sym);
    if (!m) throw new Error(`label ${name} not in the symbol file`);
    return parseInt(m[1], 16);
  };
  const tlp = label('total_levels_played');
  const ln = label('level_number');
  // sta zp (85 xx) or sta abs (8d lo hi), depending on the address
  const sta = (a: number) => (a < 0x100 ? [0x85, a] : [0x8d, a & 0xff, a >> 8]);
  const head = [...sta(tlp), 0xa9];
  const pat = [...head, 0xff, ...sta(ln)];
  const hits: number[] = [];
  for (let i = 2; i + pat.length <= prg.length; i++) if (pat.every((b, k) => prg[i + k] === b)) hits.push(i);
  if (hits.length !== 1) throw new Error(`new-game code found ${hits.length} times (expected once)`);
  const out = new Uint8Array(prg);
  out[hits[0] + head.length] = (level - 1) & 0xff;
  return out;
}

export function createApi(o: ApiOptions) {
  const kickass = o.kickass ?? process.env.KICKASS ?? '/opt/KickAss.jar';
  const java = o.java ?? process.env.KICKASS_JAVA ?? 'java';
  const buildsDir = o.buildsDir ?? process.env.BUILDS_DIR ?? join(tmpdir(), 'thrust-level-editor', 'builds');
  const keepBuilds = o.keepBuilds ?? 12;
  const timeoutMs = o.timeoutMs ?? Number(process.env.BUILD_TIMEOUT_MS ?? 120_000);
  const maxQueue = o.maxQueue ?? Number(process.env.BUILD_MAX_QUEUE ?? 8);
  let queue: Promise<unknown> = Promise.resolve();
  let pending = 0;

  const readSource = () => {
    const levelsAsm = readFileSync(join(o.modDir, SOURCE_FILES.levelsAsm), 'utf8');
    const tablesAsm = readFileSync(join(o.modDir, SOURCE_FILES.tablesAsm), 'utf8');
    return { levelsAsm, tablesAsm, hash: sourceHash(levelsAsm, tablesAsm) };
  };

  const prune = (dir: string, keep: number) => {
    if (!existsSync(dir)) return;
    const names = readdirSync(dir).sort();
    for (const n of names.slice(0, Math.max(0, names.length - keep))) rmSync(join(dir, n), { recursive: true, force: true });
  };

  function runBuild(levelsAsm: string, tablesAsm: string, startLevel: number | null): Promise<BuildResult> {
    const t0 = Date.now();
    const id = `${t0.toString(36)}-${randomBytes(3).toString('hex')}`;
    const dir = join(buildsDir, id);
    mkdirSync(dir, { recursive: true });
    cpSync(o.modDir, join(dir, 'src'), { recursive: true });
    writeFileSync(join(dir, 'src', SOURCE_FILES.levelsAsm), levelsAsm);
    writeFileSync(join(dir, 'src', SOURCE_FILES.tablesAsm), tablesAsm);
    const out = join(dir, 'out');
    mkdirSync(out);
    return new Promise((resolve) => {
      execFile(
        java,
        ['-jar', kickass, join(dir, 'src', 'thrust.asm'), '-odir', '../out', '-vicesymbols', '-symbolfile'],
        { cwd: dir, timeout: timeoutMs, maxBuffer: 16 * 1024 * 1024 },
        (err, stdout, stderr) => {
          const timedOut = !!err && err.killed;
          let log = `${stdout}${stderr}${err && !stdout && !stderr && !timedOut ? String(err) : ''}`;
          if (timedOut) log += `\n[editor] build stopped after ${timeoutMs / 1000} s\n`;
          writeFileSync(join(out, 'kickass.log'), log);
          const prgPath = join(out, 'thrust.prg');
          const errors = parseKickAssErrors(log);
          if (timedOut)
            errors.push({ message: `build took longer than ${timeoutMs / 1000} s`, line: 0, column: 0, file: 'thrust.asm' });
          const ok = !err && existsSync(prgPath) && errors.length === 0;
          const res: BuildResult = { id, ok, errors, log, ms: 0, files: ['kickass.log'], startLevel: null };
          if (ok) {
            const prg = readFileSync(prgPath);
            res.prgBytes = prg.length;
            res.files.push('thrust.prg', 'thrust.sym', 'thrust.vs');
            try {
              if (startLevel !== null && startLevel > 0) {
                writeFileSync(join(out, 'play.prg'), patchStartLevel(prg, readFileSync(join(out, 'thrust.sym'), 'utf8'), startLevel));
                res.startLevel = startLevel;
              } else copyFileSync(prgPath, join(out, 'play.prg'));
              res.files.push('play.prg');
            } catch (e) {
              res.log += `\n[editor] could not set the start level: ${e}\n`;
              copyFileSync(prgPath, join(out, 'play.prg'));
              res.files.push('play.prg');
            }
          }
          res.ms = Date.now() - t0;
          prune(buildsDir, keepBuilds);
          resolve(res);
        },
      );
    });
  }

  return async function api(req: IncomingMessage, res: ServerResponse, next?: Next) {
    const url = new URL(req.url ?? '/', 'http://localhost');
    if (!url.pathname.startsWith('/api/')) return next ? next() : notFound(res);
    try {
      if (url.pathname === '/api/source' && req.method === 'GET') {
        const layout = readLayout(readFileSync(join(o.modDir, 'thrust.asm'), 'utf8'));
        return json(res, 200, { name: 'packages/thrusty-levels/src', ...readSource(), layout });
      }
      if (url.pathname === '/api/template' && req.method === 'GET') {
        if (!o.template || !existsSync(o.template)) return notFound(res);
        res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-cache' });
        return res.end(readFileSync(o.template));
      }
      if (url.pathname === '/api/build' && req.method === 'POST') {
        const body = await readJson(req);
        if (typeof body.levelsAsm !== 'string' || typeof body.tablesAsm !== 'string')
          return json(res, 400, { error: 'levelsAsm and tablesAsm are required' });
        const { levelsAsm, tablesAsm } = body;
        const start = Number.isInteger(body.startLevel) ? Number(body.startLevel) : null;
        if (pending >= maxQueue) return json(res, 503, { error: 'the build server is busy: try again in a moment' });
        pending++;
        const run = queue.then(() => runBuild(levelsAsm, tablesAsm, start)).finally(() => pending--);
        queue = run.catch(() => undefined);
        return json(res, 200, await run);
      }
      const m = /^\/api\/builds\/([\w-]+)\/([\w.-]+)$/.exec(url.pathname);
      if (m && req.method === 'GET' && BUILD_FILES.has(m[2])) {
        const path = join(buildsDir, m[1], 'out', m[2]);
        if (!existsSync(path)) return notFound(res);
        const data = readFileSync(path);
        res.writeHead(200, {
          'Content-Type': m[2].endsWith('.prg') ? 'application/octet-stream' : 'text/plain; charset=utf-8',
          'Content-Length': data.length,
          'Content-Disposition': `inline; filename="${m[2]}"`,
          'Access-Control-Allow-Origin': '*', // so c64-ready on another origin can load it
          'Access-Control-Allow-Private-Network': 'true', // ...even a public page (Chrome)
          'Cache-Control': 'no-store',
        });
        return res.end(data);
      }
      if (req.method === 'OPTIONS') {
        res.writeHead(204, {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET',
          'Access-Control-Allow-Private-Network': 'true',
        });
        return res.end();
      }
      return notFound(res);
    } catch (e) {
      return json(res, 500, { error: String(e instanceof Error ? e.message : e) });
    }
  };
}

function json(res: ServerResponse, status: number, body: unknown) {
  const data = JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(data);
}

function notFound(res: ServerResponse) {
  json(res, 404, { error: 'not found' });
}

function readJson(req: IncomingMessage): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on('data', (c: Buffer) => {
      size += c.length;
      if (size > MAX_BODY) {
        reject(new Error('request too large'));
        req.destroy();
      } else chunks.push(c);
    });
    req.on('end', () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'));
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}
