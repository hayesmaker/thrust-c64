// End to end: edit a level, build the mod with KickAssembler in a temp copy,
// read the PRG back with tools/level2json.py and compare.
// Skipped when java, KickAss or python3 is missing.
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { decodeLevel, loadProject, saveProject, touchWall } from '../src/model/level';
import { doorWallX } from '../src/model/door';
import { ANCHOR_ROW } from '../src/model/terrain';

const ROOT = join(import.meta.dirname, '../../..');
const KICKASS = process.env.KICKASS ?? '/opt/KickAss.jar';
const has = (cmd: string, args: string[]) => {
  try {
    execFileSync(cmd, args, { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
};
const canBuild = existsSync(KICKASS) && has('java', ['-version']) && has('python3', ['--version']);

describe.skipIf(!canBuild)('KickAssembler build', () => {
  it('edited level 0 builds and the PRG decodes to the edited terrain', () => {
    const src = join(ROOT, 'packages/thrusty-levels/src');
    const p = loadProject(readFileSync(join(src, 'levels.asm'), 'utf8'), readFileSync(join(src, 'level_tables.asm'), 'utf8'));
    const l = p.levels[0];
    // a new left wall: ledge, steep staircase, shallow slope, long vertical
    l.left.points = [
      { row: ANCHOR_ROW, x: 0 },
      { row: 429, x: 0 },
      { row: 430, x: 0x50 },
      { row: 470, x: 0x56 },
      { row: 480, x: 0x7a },
      { row: 900, x: 0x7a },
    ];
    touchWall(l.left);
    l.objects.push({ type: 4, x: 0x90, y: 0x220, gun: 0 });
    const out = saveProject(p);

    const dir = mkdtempSync(join(tmpdir(), 'thrust-editor-'));
    try {
      cpSync(src, join(dir, 'src'), { recursive: true });
      writeFileSync(join(dir, 'src/levels.asm'), out.levelsAsm);
      writeFileSync(join(dir, 'src/level_tables.asm'), out.tablesAsm);
      execFileSync('java', ['-jar', KICKASS, join(dir, 'src/thrust.asm'), '-odir', '../build', '-symbolfile'], {
        stdio: 'pipe',
      });
      const json = join(dir, 'levels.json');
      execFileSync('python3', [join(ROOT, 'tools/level2json.py'), join(dir, 'build/thrust.prg'), json], { stdio: 'pipe' });
      const built = JSON.parse(readFileSync(json, 'utf8')).levels[0];
      const rows = built.walls.left.xs.length;
      const d = decodeLevel(l, rows);
      expect(built.walls.left.xs).toEqual(d.left);
      expect(built.walls.right.xs).toEqual(d.right);
      expect(built.objects).toEqual(l.objects);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }, 60_000);

  /** Build sources in a temp copy of the mod; returns a reader of runtime
   *  bytes by label (main block code runs relocated, see RELOC_OFFSET). */
  function buildMod(levelsAsm: string, tablesAsm: string): (label: string, n: number) => number[] {
    const src = join(ROOT, 'packages/thrusty-levels/src');
    const dir = mkdtempSync(join(tmpdir(), 'thrust-editor-'));
    try {
      cpSync(src, join(dir, 'src'), { recursive: true });
      writeFileSync(join(dir, 'src/levels.asm'), levelsAsm);
      writeFileSync(join(dir, 'src/level_tables.asm'), tablesAsm);
      execFileSync('java', ['-jar', KICKASS, join(dir, 'src/thrust.asm'), '-odir', '../build', '-symbolfile'], { stdio: 'pipe' });
      const prg = readFileSync(join(dir, 'build/thrust.prg'));
      const sym = new Map(
        [...readFileSync(join(dir, 'build/thrust.sym'), 'utf8').matchAll(/\.label (\w+)=\$([0-9a-f]+)/gi)].map((m) => [m[1], parseInt(m[2], 16)]),
      );
      const base = prg[0] | (prg[1] << 8);
      const RELOC = 0x8280 - 0x3000;
      return (label, n) => {
        const a = sym.get(label);
        if (a === undefined) throw new Error(`no symbol ${label}`);
        const load = a >= 0x8283 ? a - RELOC : a;
        return [...prg.subarray(2 + load - base, 2 + load - base + n)];
      };
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }

  it('doors, rules and the round cycle land in the PRG', () => {
    const src = join(ROOT, 'packages/thrusty-levels/src');
    const p = loadProject(readFileSync(join(src, 'levels.asm'), 'utf8'), readFileSync(join(src, 'level_tables.asm'), 'utf8'));
    p.levels[0].door = { side: 'right', top: 0x1c0, mode: 'slide', rows: [0x90, 0x91, 0x92, 0x93], max: 8, openX: 0, time: 0xc0 };
    p.levels[0].rules = { reverse: 'on', invisible: 'off' };
    p.levels[3].door = null;
    p.roundCycle = [{ reverse: false, invisible: false }, { reverse: false, invisible: true }];
    const out = saveProject(p);
    const rd = buildMod(out.levelsAsm, out.tablesAsm);
    expect(rd('level_door_rows', 6)).toEqual([4, 0, 0, 0, 21, 15]);
    expect(rd('level_door_mode', 6)).toEqual([0x80, 0, 0, 0, 0x40, 0]);
    expect(rd('level_door_top_LO', 1)).toEqual([0xc0]);
    expect(rd('level_door_top_HI', 1)).toEqual([0x01]);
    expect(rd('level_door_time', 1)).toEqual([0xc0]);
    expect(rd('level_0_door_x', 4)).toEqual([0x90, 0x91, 0x92, 0x93]);
    expect(rd('level_rule_reverse', 6)).toEqual([1, 0, 0, 0, 0, 0]);
    expect(rd('level_rule_invisible', 6)).toEqual([2, 0, 0, 0, 0, 0]);
    expect(rd('round_cycle_reverse', 4)).toEqual([0, 0, 0, 0xff]); // 2 entries, then round_cycle_invisible
    expect(doorWallX(p.levels[0].door!, 8)).toEqual([0x98, 0x99, 0x9a, 0x9b]);
  }, 60_000);

  it('a game made before doors were data builds with the original doors', () => {
    const p = loadProject(readFileSync(join(ROOT, 'src/levels.asm'), 'utf8'), readFileSync(join(ROOT, 'src/level_tables.asm'), 'utf8'));
    const out = saveProject(p);
    const rd = buildMod(out.levelsAsm, out.tablesAsm);
    expect(rd('level_door_rows', 6)).toEqual([0, 0, 0, 13, 21, 15]);
    expect(rd('level_5_door_x', 15)).toEqual([0xc0, 0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc6, 0xc5, 0xc4, 0xc3, 0xc2, 0xc1, 0xc0]);
  }, 60_000);

  it.each([
    ['SUPER THRUSTY MAKER', 10],
    ['A'.repeat(28), 6],
    ['AB', 19],
  ])('title "%s" is centred at column %i', (title, col) => {
    const src = join(ROOT, 'packages/thrusty-levels/src');
    const p = loadProject(readFileSync(join(src, 'levels.asm'), 'utf8'), readFileSync(join(src, 'level_tables.asm'), 'utf8'));
    const out = saveProject(p, { title, author: title.slice(3) });
    const rd = buildMod(out.levelsAsm, out.tablesAsm);
    const bytes = (row: number, text: string) => {
      const pos = 0x6000 + row * 320 + col * 8;
      return [pos & 0xff, pos >> 8, ...[...text].map((c) => c.charCodeAt(0)), 0xff];
    };
    expect(rd('msg_title', 3 + title.length)).toEqual(bytes(15, title));
    // "BY " + the author: as long as the title, so in the same column
    if (title.length > 3) expect(rd('msg_author', 3 + title.length)).toEqual(bytes(16, 'BY ' + title.slice(3)));
  }, 60_000);
});
