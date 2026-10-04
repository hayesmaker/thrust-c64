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

  it('original levels: only the door notes as info', () => {
    const infos = load().levels.flatMap(validateLevel);
    expect(infos.map((i) => i.level)).toEqual([3, 4, 5]);
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
  it('original levels add up to the measured 892 bytes', () => {
    const total = load().levels.reduce((n, l) => n + levelBytes(l).total, 0);
    expect(total).toBe(ORIGINAL_LEVEL_BYTES);
  });
});

import { memoryAreas, memoryIssues, worstState } from '../src/model/validate';

describe('memoryAreas', () => {
  const area = { levelsArea: { start: 0x1000, end: 0x2000 } };

  it('original layout: one main-block area with the original 348 bytes free', () => {
    const [a] = memoryAreas(load().levels, null);
    expect(a).toMatchObject({ id: 'main', used: 892, budget: 1240, free: 348, state: 'ok' });
  });

  it('levels area layout: terrain + objects in $1000-$1FFF, restarts in the main block', () => {
    const [lv, main] = memoryAreas(load().levels, area);
    expect(lv).toMatchObject({ id: 'levels', used: 790, budget: 4096, state: 'ok' });
    expect(main).toMatchObject({ id: 'main', used: 102, budget: 1240, state: 'ok' });
  });

  it('gets tight, then over, as objects are added', () => {
    const levels = load().levels;
    const add = (n: number) => {
      for (let k = 0; k < n; k++) levels[0].objects.push({ type: 4, x: 0, y: 0x200, gun: 0 });
    };
    add(50); // +250 bytes: 1142 of 1240, 98 free (< 10% = 124)
    let areas = memoryAreas(levels, null);
    expect(areas[0].state).toBe('tight');
    expect(memoryIssues(areas, 0)[0]).toMatchObject({ severity: 'warn' });
    add(30); // 248 more bytes in total than the budget allows
    areas = memoryAreas(levels, null);
    expect(areas[0].state).toBe('over');
    expect(worstState(areas)).toBe('over');
    expect(memoryIssues(areas, 0)[0].message).toMatch(/^out of memory: .* 52 bytes over/);
    // the same data fits easily in the levels area
    expect(worstState(memoryAreas(levels, area))).toBe('ok');
  });
});
