import { describe, expect, it } from 'vitest';
import fixture from './fixtures/original_levels.json';
import { gunArc, gunParam, isSolid, snapObject } from '../src/model/objects';

const cases = fixture.levels.flatMap((l) =>
  l.objects.map((o, i) => ({ name: `level ${l.level} object ${i} (type ${o.type})`, o, l })),
);

describe('snapObject', () => {
  it.each(cases)('$name is already where the snap rule puts it', ({ o, l }) => {
    const { left, right } = { left: l.walls.left.xs, right: l.walls.right.xs };
    expect(snapObject(o, left, right)).toEqual({ x: o.x, y: o.y });
  });

  it.each(cases)('$name snaps back from 6 rows / 3 units away', ({ o, l }) => {
    const left = l.walls.left.xs;
    const right = l.walls.right.xs;
    const moved = o.type >= 7 ? { ...o, x: o.x + (o.type === 7 ? 3 : -3) } : { ...o, y: o.y - 6 };
    expect(snapObject(moved, left, right)).toEqual({ x: o.x, y: o.y });
  });
});

describe('guns', () => {
  it('arc runs from base to base + mask + 3', () => {
    expect(gunArc(0x1e)).toEqual({ from: 28, to: 38 });
    expect(gunArc(0x04)).toEqual({ from: 4, to: 8 });
  });
  it('gunParam keeps unused high bits', () => {
    expect(gunParam(8, 3, 0xe0)).toBe(0xeb);
  });
  it('isSolid wraps X', () => {
    expect(isSolid([10], [200], 256 + 5, 0)).toBe(true);
    expect(isSolid([10], [200], 256 + 50, 0)).toBe(false);
  });
});
