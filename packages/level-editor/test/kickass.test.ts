// End to end: edit a level, build the mod with KickAssembler in a temp copy,
// read the PRG back with tools/level2json.py and compare.
// Skipped when java, KickAss or python3 is missing.
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { decodeLevel, loadProject, saveProject, touchWall } from '../src/model/level';
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
});
