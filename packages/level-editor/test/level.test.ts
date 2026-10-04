import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import fixture from './fixtures/original_levels.json';
import { blockBytes, blockValues, parseAsm, serializeAsm, writeBlock } from '../src/model/asm';
import { decodeLevel, loadProject, saveProject, touchWall, wallTables } from '../src/model/level';
import { decodeWall } from '../src/model/terrain';

const ROOT = join(import.meta.dirname, '../../..');
const read = (p: string) => readFileSync(join(ROOT, p), 'utf8');
const ORIG = { levels: read('src/levels.asm'), tables: read('src/level_tables.asm') };
const MOD = {
  levels: read('packages/thrusty-levels/src/levels.asm'),
  tables: read('packages/thrusty-levels/src/level_tables.asm'),
};

describe('asm', () => {
  it('parses multi-line blocks and expressions', () => {
    const doc = parseAsm(ORIG.tables);
    expect(blockBytes(doc, 'level_2_reset_data')).toHaveLength(18);
    expect(blockValues(doc, 'level_reset_ptr2_table_LO')[2]).toBe('<(level_2_reset_data+3)');
  });

  it('unchanged write is a no-op', () => {
    const doc = parseAsm(ORIG.levels);
    expect(writeBlock(doc, 'level_0_obj_pos_X', blockBytes(doc, 'level_0_obj_pos_X'))).toBe(false);
    expect(serializeAsm(doc)).toBe(ORIG.levels);
  });

  it('growing a multi-line block shifts later blocks', () => {
    const doc = parseAsm(ORIG.levels);
    writeBlock(doc, 'level_4_obj_pos_X', new Array(40).fill(1));
    const again = parseAsm(serializeAsm(doc));
    expect(blockBytes(again, 'level_4_obj_pos_X')).toEqual(new Array(40).fill(1));
    expect(blockBytes(again, 'level_4_obj_pos_Y')).toEqual(blockBytes(parseAsm(ORIG.levels), 'level_4_obj_pos_Y'));
  });
});

describe('loadProject (original source)', () => {
  const p = loadProject(ORIG.levels, ORIG.tables);

  it.each(fixture.levels)('level $level matches the PRG', (f) => {
    const l = p.levels[f.level];
    const rows = f.walls.left.xs.length;
    const d = decodeLevel(l, rows);
    expect(d.left).toEqual(f.walls.left.xs);
    expect(d.right).toEqual(f.walls.right.xs);
    expect(l.objects).toEqual(f.objects);
    expect(l.restarts).toEqual(f.restarts);
    expect(l.gravity).toBe(f.gravity);
    expect(l.colours).toEqual(f.colours);
  });
});

describe('saveProject', () => {
  it.each([
    ['original', ORIG],
    ['thrusty-levels', MOD],
  ])('%s: save without edits reproduces both files exactly', (_, src) => {
    const out = saveProject(loadProject(src.levels, src.tables));
    expect(out.levelsAsm).toBe(src.levels);
    expect(out.tablesAsm).toBe(src.tables);
  });

  it('edited wall is re-encoded and reloads to the same rows', () => {
    const p = loadProject(ORIG.levels, ORIG.tables);
    const w = p.levels[0].left;
    w.points[3] = { row: w.points[3].row, x: w.points[3].x + 7 };
    touchWall(w);
    const expected = decodeWall(wallTables(w), 0, 600);
    const out = saveProject(p);
    const q = loadProject(out.levelsAsm, out.tablesAsm);
    expect(decodeWall(wallTables(q.levels[0].left), 0, 600)).toEqual(expected);
    // other levels untouched
    expect(q.levels[3].left.raw).toEqual(p.levels[3].left.raw);
  });

  it('objects, restart points and settings round trip', () => {
    const p = loadProject(ORIG.levels, ORIG.tables);
    const l = p.levels[1];
    l.objects.push({ type: 4, x: 0x90, y: 0x220, gun: 0 });
    l.restarts.push({ shipX: 0x80, shipY: 0x250, windowX: 0x6a, windowY: 0x1ec });
    l.gravity = 0x0a;
    l.colours.terrain = 0x0b;
    const out = saveProject(p);
    const q = loadProject(out.levelsAsm, out.tablesAsm);
    expect(q.levels[1].objects).toEqual(l.objects);
    expect(q.levels[1].restarts).toEqual(l.restarts);
    expect(q.levels[1].gravity).toBe(0x0a);
    expect(q.levels[1].colours.terrain).toBe(0x0b);
    expect(blockValues(parseAsm(out.tablesAsm), 'level_reset_ptr2_table_LO')[1]).toBe('<(level_1_reset_data+2)');
    expect(blockBytes(parseAsm(out.tablesAsm), 'level_reset_data_sizes')[1]).toBe(2);
    expect(q.levels[2]).toEqual(p.levels[2]);
  });

  it('a wall edited and then restored saves as the original', () => {
    const p = loadProject(ORIG.levels, ORIG.tables);
    const w = p.levels[0].left;
    const before = structuredClone(w);
    w.points[3] = { row: w.points[3].row, x: w.points[3].x + 7 };
    touchWall(w);
    saveProject(p);
    p.levels[0].left = before;
    expect(saveProject(p).levelsAsm).toBe(ORIG.levels);
  });
});
