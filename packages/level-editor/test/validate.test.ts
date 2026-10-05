import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { loadProject } from '../src/model/level';
import { ORIGINAL_LEVEL_BYTES, levelBytes, validateLevel } from '../src/model/validate';

const ROOT = join(import.meta.dirname, '../../..');
const read = (p: string) => readFileSync(join(ROOT, p), 'utf8');
const load = () => loadProject(read('src/levels.asm'), read('src/level_tables.asm'));

describe('validateLevel', () => {
  it('original levels have no errors or warnings', () => {
    const issues = load().levels.flatMap(validateLevel).filter((i) => i.severity !== 'info');
    expect(issues).toEqual([]);
  });

  it('original levels: no notes either', () => {
    expect(load().levels.flatMap(validateLevel)).toEqual([]);
  });

  it('checks doors and switches', () => {
    const levels = load().levels;
    const msgs = (l: (typeof levels)[number]) => validateLevel(l).map((i) => `${i.severity}: ${i.message}`);
    const l3 = levels[3];
    l3.objects = l3.objects.filter((o) => o.type !== 7 && o.type !== 8);
    expect(msgs(l3)).toContain('warn: the door has no door switch (object 7 or 8) to open it');
    l3.door!.max = 0;
    expect(msgs(l3).some((m) => m.startsWith('warn: door row 0 still reaches the right wall when fully open'))).toBe(true);
    const l4 = levels[4];
    l4.door!.max = 30;
    expect(msgs(l4)).toContain('error: the door opens 30 rows but has only 21');
    const l5 = levels[5];
    l5.door = null;
    expect(msgs(l5)).toContain('info: 2 door switches but no door: they do nothing');
    const l0 = levels[0];
    l0.door = { side: 'left', top: 0x200, mode: 'slide', rows: [4], max: 10, openX: 0, time: 0xff };
    expect(msgs(l0)).toContain('error: door row 0: opening 10 takes X past 0');
  });

  it('catches broken rules', () => {
    const l = load().levels[2];
    l.objects.reverse(); // pod stand no longer first, fuel moves past slot 12? (13 objects)
    l.objects.push({ type: 4, x: 0x80, y: 0x100, gun: 0 }); // fuel at index 13, floating in the sky
    l.restarts.reverse();
    const msgs = validateLevel(l).map((i) => `${i.severity}: ${i.message}`);
    expect(msgs).toContain('error: object 0 must be the pod stand');
    expect(msgs.some((m) => m.startsWith('error: object 13 (fuel) must be among the first 12'))).toBe(true);
    expect(msgs.some((m) => m.includes('restart 1 is above restart 0'))).toBe(true);
    expect(msgs.some((m) => m.includes('object 13 (fuel) has no terrain to rest on'))).toBe(true);
  });
});

describe('levelBytes', () => {
  it('original levels add up to the measured 892 bytes, plus 52 of doors', () => {
    const levels = load().levels;
    const total = levels.reduce((n, l) => n + levelBytes(l).total, 0);
    const doors = levels.reduce((n, l) => n + levelBytes(l).door, 0);
    expect(doors).toBe(1 + 1 + 1 + 13 + 21 + 15);
    expect(total - doors).toBe(ORIGINAL_LEVEL_BYTES);
  });
});

import { memoryAreas, memoryIssues, worstState } from '../src/model/validate';

describe('memoryAreas', () => {
  const area = { levelsArea: { start: 0x1000, end: 0x2000 } };

  it('original layout: one main-block area (with the door shapes)', () => {
    const [a] = memoryAreas(load().levels, null);
    expect(a).toMatchObject({ id: 'main', used: 944, budget: 1240, free: 296, state: 'ok' });
  });

  it('levels area layout: terrain + objects + doors in $1000-$1FFF, restarts in the main block', () => {
    const [lv, main] = memoryAreas(load().levels, area);
    expect(lv).toMatchObject({ id: 'levels', used: 842, budget: 4096, state: 'ok' });
    expect(main).toMatchObject({ id: 'main', used: 102, budget: 1179, state: 'ok' });
    // each round past the original four costs 2 bytes
    expect(memoryAreas(load().levels, area, 6)[1].used).toBe(106);
  });

  it('gets tight, then over, as objects are added', () => {
    const levels = load().levels;
    const add = (n: number) => {
      for (let k = 0; k < n; k++) levels[0].objects.push({ type: 4, x: 0, y: 0x200, gun: 0 });
    };
    add(40); // +200 bytes: 1144 of 1240, 96 free (< 10% = 124)
    let areas = memoryAreas(levels, null);
    expect(areas[0].state).toBe('tight');
    expect(memoryIssues(areas, 0)[0]).toMatchObject({ severity: 'warn' });
    add(30); // 1294: 54 more bytes than the budget allows
    areas = memoryAreas(levels, null);
    expect(areas[0].state).toBe('over');
    expect(worstState(areas)).toBe('over');
    expect(memoryIssues(areas, 0)[0].message).toMatch(/^out of memory: .* 54 bytes over/);
    // the same data fits easily in the levels area
    expect(worstState(memoryAreas(levels, area))).toBe('ok');
  });
});
