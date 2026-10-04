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
