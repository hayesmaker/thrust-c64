import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import fixture from './fixtures/original_levels.json';
import { blockBytes, blockValues, parseAsm, serializeAsm, writeBlock } from '../src/model/asm';
import { ORIGINAL_DOORS, defaultRoundCycle, doorShapesAsm, doorTablesAsm, upgradeSources } from '../src/model/door';
import { decodeLevel, loadProject, saveProject, touchWall, upgradeLevels, wallTables } from '../src/model/level';
import { decodeWall } from '../src/model/terrain';

const ROOT = join(import.meta.dirname, '../../..');
const read = (p: string) => readFileSync(join(ROOT, p), 'utf8');
const ORIG = { levels: read('src/levels.asm'), tables: read('src/level_tables.asm') };
/** The original sources with the door / rule tables added (what loading them gives). */
const ORIG_UP = (() => {
  const u = upgradeSources(ORIG.levels, ORIG.tables);
  return { levels: u.levelsAsm, tables: u.tablesAsm };
})();
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
    ['original', ORIG, ORIG_UP],
    ['thrusty-levels', MOD, MOD],
  ])('%s: save without edits reproduces both files exactly', (_, src, want) => {
    const out = saveProject(loadProject(src.levels, src.tables));
    expect(out.levelsAsm).toBe(want.levels);
    expect(out.tablesAsm).toBe(want.tables);
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

  it('unedited walls from other sources are written (original levels into the mod)', () => {
    const orig = loadProject(ORIG.levels, ORIG.tables);
    const p = loadProject(MOD.levels, MOD.tables);
    p.levels = orig.levels;
    const out = saveProject(p);
    const q = loadProject(out.levelsAsm, out.tablesAsm);
    for (let n = 0; n < 6; n++) expect(decodeLevel(q.levels[n])).toEqual(decodeLevel(orig.levels[n]));
  });

  it('examples/template.json holds the original levels (remake: npm run mod-to-game -- --original)', () => {
    const t = JSON.parse(read('packages/thrusty-levels/examples/template.json'));
    const orig = loadProject(ORIG.levels, ORIG.tables);
    const fromSources = loadProject(t.levelsAsm, t.tablesAsm);
    for (let n = 0; n < 6; n++) {
      expect(t.levels[n]).toEqual(orig.levels[n]);
      expect(fromSources.levels[n]).toEqual(orig.levels[n]);
    }
    expect(t.roundCycle).toEqual(orig.roundCycle);
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
    expect(saveProject(p).levelsAsm).toBe(ORIG_UP.levels);
  });
});

describe('doors and rules', () => {
  it('the mod source has exactly the tables that upgrading older sources adds', () => {
    expect(MOD.tables).toContain(doorTablesAsm());
    expect(MOD.levels).toContain(doorShapesAsm());
    const u = upgradeSources(MOD.levels, MOD.tables);
    expect(u).toEqual({ levelsAsm: MOD.levels, tablesAsm: MOD.tables });
  });

  it('older sources load with the original doors, rules and round cycle', () => {
    const p = loadProject(ORIG.levels, ORIG.tables);
    p.levels.forEach((l, n) => {
      expect(l.door).toEqual(ORIGINAL_DOORS[n] ?? null);
      expect(l.rules).toEqual({ reverse: 'round', invisible: 'round' });
    });
    expect(p.roundCycle).toEqual(defaultRoundCycle());
    expect(p.levelsAsm).toBe(ORIG_UP.levels);
  });

  it('doors, rules and the round cycle round trip', () => {
    const p = loadProject(MOD.levels, MOD.tables);
    p.levels[0].door = { side: 'right', top: 0x1a3, mode: 'slide', rows: [0x40, 0x41, 0x42], max: 6, openX: 0, time: 0x80 };
    p.levels[4].door = { ...p.levels[4].door!, rows: new Array(30).fill(0xa0), max: 0x1e, openX: 0x90 };
    p.levels[5].door = null;
    p.levels[2].rules = { reverse: 'on', invisible: 'invert' };
    p.roundCycle = [{ reverse: false, invisible: true }, { reverse: true, invisible: false }];
    const out = saveProject(p);
    const q = loadProject(out.levelsAsm, out.tablesAsm);
    expect(q.levels.map((l) => l.door)).toEqual(p.levels.map((l) => l.door));
    expect(q.levels.map((l) => l.rules)).toEqual(p.levels.map((l) => l.rules));
    expect(q.roundCycle).toEqual(p.roundCycle);
    const T = parseAsm(out.tablesAsm);
    expect(blockBytes(T, 'level_door_mode')).toEqual([0x80, 0, 0, 0, 0x40, 0]);
    expect(blockBytes(T, 'level_door_rows')).toEqual([3, 0, 0, 13, 30, 0]);
    expect(blockBytes(parseAsm(out.levelsAsm), 'level_5_door_x')).toEqual([0]);
    expect(blockBytes(T, 'round_cycle_reverse')).toEqual([0, 0xff]);
    expect(blockBytes(T, 'level_rule_reverse')).toEqual([0, 0, 1, 0, 0, 0]);
    expect(blockBytes(T, 'level_rule_invisible')).toEqual([0, 0, 3, 0, 0, 0]);
  });

  it('levels from older game files get doors and rules from their sources', () => {
    const p = loadProject(ORIG.levels, ORIG.tables);
    const old = p.levels.map(({ door, rules, ...l }) => (void door, void rules, l));
    const up = upgradeLevels(p, old as never);
    expect(up.map((l) => l.door)).toEqual(p.levels.map((l) => l.door));
    expect(up[0].rules).toEqual({ reverse: 'round', invisible: 'round' });
    // a level saved without a door stays without one
    expect(upgradeLevels(p, [{ ...p.levels[3], door: null }])[0].door).toBeNull();
  });
});

import { DEFAULT_TITLE, TITLE_MAX, authorText, titleAsm, titleColumn, titleText } from '../src/model/title';

describe('title', () => {
  it('keeps what the font can show, upper case, at most 28 characters', () => {
    expect(titleText('Andy\'s big-caves_2!')).toBe('ANDYS BIG CAVES 2');
    expect(titleText('  v1.2   final ')).toBe('V1.2 FINAL');
    expect(titleText('x'.repeat(40))).toHaveLength(TITLE_MAX);
    expect(titleText('???')).toBe(DEFAULT_TITLE);
  });

  it('is centred like the assembler does it', () => {
    expect(titleColumn(DEFAULT_TITLE)).toBe(10);
    expect(titleColumn('A'.repeat(28))).toBe(6);
    expect(titleColumn('AB')).toBe(19);
  });

  it('author line: "BY " + the name, 28 characters in all; empty without one', () => {
    expect(authorText('andy h.')).toBe('BY ANDY H.');
    expect(authorText('a'.repeat(40))).toHaveLength(TITLE_MAX);
    expect(authorText('  ')).toBe('');
  });

  it('the mod source has the default title block that older sources get', () => {
    expect(MOD.tables).toContain(titleAsm());
  });

  // earlier versions of the title section, which carried their own positions
  const oldTitleOnly = [
    '// ----------------------------------------------------------------------------',
    "// Title screen line (row 16 of the high score screen): the game's name, ASCII,",
    '// ----------------------------------------------------------------------------',
    'msg_title:',
    '    .byte <title_pos, >title_pos',
    'msg_title_text:',
    '    .byte $41,$42',
    'msg_title_end:',
    '    .byte $ff',
    '.label title_pos = $6000 + 16 * 320 + floor((40 - (msg_title_end - msg_title_text)) / 2) * 8',
    '.errorif msg_title_end - msg_title_text > 28, "too long"',
  ].join('\n');
  const oldRow14 = [
    '// ----------------------------------------------------------------------------',
    "// Title screen lines (high score screen): the game's name on row 14 and its",
    '// ----------------------------------------------------------------------------',
    'msg_title:',
    '    .byte <title_pos, >title_pos',
    'msg_title_text:',
    '    .byte $41,$42',
    'msg_title_end:',
    '    .byte $ff',
    '.label title_pos = $6000 + 14 * 320 + floor((40 - (msg_title_end - msg_title_text)) / 2) * 8',
    '.errorif msg_title_end - msg_title_text > 28, "too long"',
    'msg_author:',
    '    .byte <author_pos, >author_pos',
    'msg_author_text:',
    '    .byte $42,$59,$20,$4d,$45',
    'msg_author_end:',
    '    .byte $ff',
    '.label author_pos = $6000 + 16 * 320 + floor((40 - (msg_author_end - msg_author_text)) / 2) * 8',
    '.errorif msg_author_end - msg_author_text > 28, "too long"',
  ].join('\n');
  const ascii = (t: string) => [...t].map((c) => c.charCodeAt(0));

  it.each([
    ['title only, row 16', oldTitleOnly, ' '],
    ['title row 14 + author, positions in the file', oldRow14, 'BY ME'],
  ])('earlier title sections (%s) become the current one, keeping their texts', (_, old, author) => {
    const tables = MOD.tables.replace(titleAsm(), old);
    expect(tables).not.toBe(MOD.tables);
    const p = loadProject(MOD.levels, tables);
    expect(p.tablesAsm).toBe(MOD.tables.replace(titleAsm(), titleAsm(ascii('AB'), ascii(author))));
    expect(p.tablesAsm).not.toMatch(/title_pos =|author_pos =/);
  });

  it('saving with a title writes msg_title_text; without one keeps it', () => {
    const p = loadProject(MOD.levels, MOD.tables);
    expect(saveProject(p).tablesAsm).toBe(MOD.tables);
    const out = saveProject(p, { title: 'Hello world', author: 'me' });
    const T = parseAsm(out.tablesAsm);
    expect(blockBytes(T, 'msg_title_text')).toEqual([...'HELLO WORLD'].map((c) => c.charCodeAt(0)));
    expect(blockBytes(T, 'msg_author_text')).toEqual([...'BY ME'].map((c) => c.charCodeAt(0)));
    const none = saveProject(loadProject(out.levelsAsm, out.tablesAsm), { author: '' });
    expect(blockBytes(parseAsm(none.tablesAsm), 'msg_author_text')).toEqual([0x20]);
  });
});

import { fontTyping } from '../src/model/title';

describe('title boxes', () => {
  it('turn what is typed into what the font shows, keeping a space being typed', () => {
    expect(fontTyping("andy's big-cave ", 28)).toBe('ANDYS BIG CAVE ');
    expect(fontTyping('  two  spaces', 28)).toBe('TWO SPACES');
    expect(fontTyping('x'.repeat(30), 25)).toHaveLength(25);
  });
});
