import { describe, expect, it } from 'vitest';
import fixture from './fixtures/original_levels.json';
import {
  ANCHOR_ROW,
  type Point,
  decodeWall,
  encodeWall,
  importWall,
  pointsToRuns,
  segmentSteps,
  tablesToPoints,
  wallRows,
} from '../src/model/terrain';

const walls = fixture.levels.flatMap((l) =>
  (['left', 'right'] as const).map((side) => ({ name: `level ${l.level} ${side}`, ...l.walls[side] })),
);

describe('decodeWall', () => {
  it.each(walls)('$name matches the Python decoder', (w) => {
    expect(decodeWall(w, w.start, w.xs.length)).toEqual(w.xs);
  });

  it.each(walls)('$name: wallRows matches', (w) => {
    expect(wallRows(w)).toBe(w.rows);
  });
});

describe('import -> encode', () => {
  it.each(walls)('$name decodes identically after a round trip', (w) => {
    const pts = importWall(w, w.start);
    const t = encodeWall(pts);
    expect(decodeWall(t, w.start, w.xs.length)).toEqual(w.xs);
  });

  it.each(walls)('$name: simplified points are no more than the runs', (w) => {
    expect(importWall(w, w.start).length).toBeLessThanOrEqual(tablesToPoints(w, w.start).length);
  });

  it('original tables that are already canonical are reproduced byte for byte', () => {
    // level 1 left: $FF,$FF,$AF,$01,$0B,$01,$17,$36,$17,$14,$0F,$01,$FF
    const l1 = fixture.levels[1].walls.left;
    expect(encodeWall(importWall(l1, 0))).toEqual({ counts: l1.counts, steps: [...l1.steps.slice(0, -1), 0] });
  });
});

describe('segmentSteps', () => {
  it('ledge', () => expect(segmentSteps(1, 75)).toEqual([75]));
  it('even slope', () => expect(segmentSteps(4, -8)).toEqual([-2, -2, -2, -2]));
  it('steep slope puts the step first', () => expect(segmentSteps(6, 2)).toEqual([1, 0, 0, 1, 0, 0]));
  it('steep negative slope', () => expect(segmentSteps(6, -2)).toEqual([-1, 0, 0, -1, 0, 0]));
  it('shallow uneven slope', () => expect(segmentSteps(2, 5)).toEqual([3, 2]));
  it('sums to dx', () => {
    for (let dy = 1; dy < 40; dy++)
      for (let dx = -60; dx <= 60; dx++) expect(segmentSteps(dy, dx).reduce((a, b) => a + b, 0)).toBe(dx);
  });
});

describe('encodeWall', () => {
  const at = (row: number, x: number): Point => ({ row, x });

  it('builds the dummy, sky and terminator entries', () => {
    const t = encodeWall([at(ANCHOR_ROW, 0), at(429, 0), at(430, 0x4b), at(441, 0x56)]);
    expect(t.counts).toEqual([0xff, 0xff, 175, 1, 11, 0xff]);
    expect(t.steps).toEqual([0, 0, 0, 0x4b, 1, 0]);
  });

  it('splits runs longer than 254 rows', () => {
    const runs = pointsToRuns([at(ANCHOR_ROW, 0), at(ANCHOR_ROW + 600, 0)]);
    expect(runs).toEqual([
      { rows: 254, step: 0 },
      { rows: 254, step: 0 },
      { rows: 92, step: 0 },
    ]);
  });

  it('wraps X: right wall going left past 0', () => {
    const pts = [at(ANCHOR_ROW, 0xff), at(300, 0xff), at(301, 0xff - 300)];
    const xs = decodeWall(encodeWall(pts), 0xff, 302);
    expect(xs[301]).toBe((0xff - 300) & 0xff);
  });

  it('rejects points that do not go down', () => {
    expect(() => encodeWall([at(ANCHOR_ROW, 0), at(300, 1), at(300, 5)])).toThrow();
    expect(() => encodeWall([at(100, 0)])).toThrow();
  });

  it('random walls decode to their points', () => {
    let seed = 1;
    const rnd = (n: number) => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) % n);
    for (let trial = 0; trial < 200; trial++) {
      const pts: Point[] = [at(ANCHOR_ROW, 0)];
      for (let k = 0; k < 12; k++) {
        const p = pts[pts.length - 1];
        pts.push(at(p.row + 1 + rnd(300), p.x + rnd(200) - 100));
      }
      const xs = decodeWall(encodeWall(pts), 0, pts[pts.length - 1].row + 5);
      for (const p of pts) expect(xs[p.row]).toBe(p.x & 0xff);
      // and importing gives back the same rows
      const again = decodeWall(encodeWall(importWall(encodeWall(pts), 0)), 0, xs.length);
      expect(again).toEqual(xs);
    }
  });
});
