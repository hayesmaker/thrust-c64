// Build API: error parsing, start-level patch, and the HTTP routes against a
// temp copy of the mod source (the real one is never touched).
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { type AddressInfo } from 'node:net';
import { createServer, type Server } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createApi, parseKickAssErrors, patchStartLevel, readLayout, sourceHash } from '../server/api.ts';

const ROOT = join(import.meta.dirname, '../../..');
const KICKASS = process.env.KICKASS ?? '/opt/KickAss.jar';
const canBuild = (() => {
  try {
    execFileSync('java', ['-version'], { stdio: 'ignore' });
    return existsSync(KICKASS);
  } catch {
    return false;
  }
})();

describe('parseKickAssErrors', () => {
  it('reads message, line, column and file', () => {
    const log = 'parsing\n\n    .byte $zz\n          ^\n\nError: Syntax error\nat line 22, column 19 in levels.asm\n\n';
    expect(parseKickAssErrors(log)).toEqual([{ message: 'Syntax error', line: 22, column: 19, file: 'levels.asm' }]);
  });
});

describe('failed .assert', () => {
  it('counts as an error (KickAssembler still writes the PRG)', () => {
    const log = '  music must end below $3000=true (true)\n  main code must end below $C000=false (true) -- ERROR IN ASSERTION!!!\n';
    expect(parseKickAssErrors(log)).toEqual([
      { message: 'assertion failed: main code must end below $C000', line: 0, column: 0, file: 'thrust.asm' },
    ]);
  });
});

describe('readLayout', () => {
  it('finds the levels area in the mod and none in the original', () => {
    expect(readLayout(readFileSync(join(ROOT, 'packages/thrusty-levels/src/thrust.asm'), 'utf8'))).toEqual({
      levelsArea: { start: 0x1000, end: 0x2000 },
    });
    expect(readLayout(readFileSync(join(ROOT, 'src/thrust.asm'), 'utf8'))).toEqual({ levelsArea: null });
  });
});

describe('patchStartLevel', () => {
  const prgPath = join(ROOT, 'build/thrust.prg');
  it.skipIf(!existsSync(prgPath))('patches the new-game level number in the original build', () => {
    const prg = readFileSync(prgPath);
    const sym = readFileSync(join(ROOT, 'build/thrust.sym'), 'utf8');
    const out = patchStartLevel(prg, sym, 3);
    const diff = [...out].map((b, i) => (b !== prg[i] ? i : -1)).filter((i) => i >= 0);
    expect(diff).toHaveLength(1);
    expect(prg[diff[0]]).toBe(0xff);
    expect(out[diff[0]]).toBe(2);
  });
});

describe('HTTP API', () => {
  let server: Server;
  let base = '';
  let tmp = '';
  let modDir = '';

  beforeAll(async () => {
    tmp = mkdtempSync(join(tmpdir(), 'thrust-api-'));
    modDir = join(tmp, 'mod');
    cpSync(join(ROOT, 'packages/thrusty-levels/src'), modDir, { recursive: true });
    const api = createApi({ modDir, buildsDir: join(tmp, 'builds'), kickass: KICKASS });
    server = createServer((req, res) => api(req, res));
    await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
    base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  });
  afterAll(() => {
    server?.close();
    rmSync(tmp, { recursive: true, force: true });
  });

  const get = async (p: string) => (await fetch(base + p)).json();
  const send = async (method: string, p: string, body: unknown) => {
    const r = await fetch(base + p, { method, body: JSON.stringify(body), headers: { 'Content-Type': 'application/json' } });
    return { status: r.status, body: await r.json() };
  };

  it('GET /api/source returns both files and their hash', async () => {
    const s = await get('/api/source');
    expect(s.levelsAsm).toBe(readFileSync(join(modDir, 'levels.asm'), 'utf8'));
    expect(s.hash).toBe(sourceHash(s.levelsAsm, s.tablesAsm));
    expect(s.layout).toEqual({ levelsArea: { start: 0x1000, end: 0x2000 } });
  });

  it('never writes the mod source (it is the template)', async () => {
    const s = await get('/api/source');
    const r = await send('PUT', '/api/source', { levelsAsm: s.levelsAsm + '// edited\n', tablesAsm: s.tablesAsm });
    expect(r.status).toBe(404);
    expect(readFileSync(join(modDir, 'levels.asm'), 'utf8')).toBe(s.levelsAsm);
  });

  it('rejects unknown routes and files', async () => {
    expect((await fetch(base + '/api/nope')).status).toBe(404);
    expect((await fetch(base + '/api/builds/x/../../etc/passwd')).status).toBe(404);
    expect((await fetch(base + '/api/builds/x/secret.txt')).status).toBe(404);
  });

  it.skipIf(!canBuild)('POST /api/build builds, patches the start level and serves the PRG', async () => {
    const s = await get('/api/source');
    const { body: b } = await send('POST', '/api/build', { levelsAsm: s.levelsAsm, tablesAsm: s.tablesAsm, startLevel: 4 });
    expect(b.ok).toBe(true);
    expect(b.startLevel).toBe(4);
    const r = await fetch(`${base}/api/builds/${b.id}/play.prg`);
    expect(r.headers.get('access-control-allow-origin')).toBe('*');
    const play = new Uint8Array(await r.arrayBuffer());
    const prg = new Uint8Array(await (await fetch(`${base}/api/builds/${b.id}/thrust.prg`)).arrayBuffer());
    expect(play.length).toBe(b.prgBytes);
    expect([...play].filter((v, i) => v !== prg[i])).toEqual([3]);
  }, 60_000);

  it.skipIf(!canBuild)('POST /api/build fails when levels.asm overflows its area', async () => {
    const s = await get('/api/source');
    // 4000 extra bytes: more than the 4 KB area can hold
    const big = s.levelsAsm.replace('level_0_obj_pos_X:\n', `level_0_obj_pos_X:\n    .fill 4000, 0\n`);
    const { body: b } = await send('POST', '/api/build', { levelsAsm: big, tablesAsm: s.tablesAsm });
    expect(b.ok).toBe(false);
    expect(b.errors[0].message).toMatch(/^levels\.asm is \d+ bytes too big for the levels area \$1000-\$1fff/i);
  }, 60_000);

  it.skipIf(!canBuild)('POST /api/build reports KickAssembler errors', async () => {
    const s = await get('/api/source');
    const broken = s.levelsAsm.replace('.byte $ff,$ff,', '.byte $ff,$zz,');
    const { body: b } = await send('POST', '/api/build', { levelsAsm: broken, tablesAsm: s.tablesAsm });
    expect(b.ok).toBe(false);
    expect(b.errors[0]).toMatchObject({ file: 'levels.asm', message: 'Syntax error' });
    expect(b.files).toEqual(['kickass.log']);
  }, 60_000);
});
