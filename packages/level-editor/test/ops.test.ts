import { describe, expect, it } from 'vitest';
import { type Wall } from '../src/model/level';
import { ANCHOR_ROW, encodeWall } from '../src/model/terrain';
import { deletePoint, insertPoint, lockSlope, movePoint, wallXAt } from '../src/editor/ops';

const wall = (): Wall => {
  const points = [
    { row: ANCHOR_ROW, x: 0 },
    { row: 429, x: 0 },
    { row: 430, x: 0x50 },
    { row: 470, x: 0x60 },
  ];
  return { start: 0, points, raw: encodeWall(points) };
};

describe('ops', () => {
  it('move clamps the row between the neighbours and drops raw', () => {
    const w = wall();
    expect(movePoint(w, 2, 900, 0x55)).toBe(true);
    expect(w.points[2]).toEqual({ row: 469, x: 0x55 });
    expect(w.raw).toBeUndefined();
    movePoint(w, 2, 0, 0x55);
    expect(w.points[2].row).toBe(430);
  });

  it('the anchor cannot move or be deleted', () => {
    const w = wall();
    expect(movePoint(w, 0, 300, 5)).toBe(false);
    expect(deletePoint(w, 0)).toBe(false);
    expect(w.raw).toBeDefined();
  });

  it('the last point can move down freely', () => {
    const w = wall();
    movePoint(w, 3, 1000, 0x10);
    expect(w.points[3]).toEqual({ row: 1000, x: 0x10 });
  });

  it('lockSlope snaps to a whole step per row', () => {
    expect(lockSlope({ row: 100, x: 10 }, 110, 23)).toBe(20); // step 1
    expect(lockSlope({ row: 100, x: 10 }, 110, 13)).toBe(10); // vertical
    expect(lockSlope({ row: 100, x: 10 }, 110, -6)).toBe(-10); // step -2
  });

  it('insert needs a free row', () => {
    const w = wall();
    expect(insertPoint(w, 2, 429, 5)).toBe(false); // ledge: no row in between
    expect(insertPoint(w, 3, 450, 0x58)).toBe(true);
    expect(w.points.map((p) => p.row)).toEqual([ANCHOR_ROW, 429, 430, 450, 470]);
    expect(insertPoint(w, 5, 500, 0x60)).toBe(true); // append below the last point
    expect(insertPoint(w, 6, 400, 0)).toBe(false);
  });

  it('wallXAt follows the drawn line', () => {
    const w = wall();
    expect(wallXAt(w, 300)).toBe(0);
    expect(wallXAt(w, 450)).toBe(0x58);
    expect(wallXAt(w, 2000)).toBe(0x60);
  });
});

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { decodeLevel, loadProject } from '../src/model/level';
import { addObject, addRestart, deleteRestart, moveObject, moveRestart, sortObjects } from '../src/editor/ops';

const ROOT = join(import.meta.dirname, '../../..');
const level = (n: number) =>
  loadProject(readFileSync(join(ROOT, 'src/levels.asm'), 'utf8'), readFileSync(join(ROOT, 'src/level_tables.asm'), 'utf8')).levels[n];

describe('object ops', () => {
  it('moving a snapped object off and back returns it to its spot', () => {
    const l = level(0);
    const d = decodeLevel(l);
    const fuel = { ...l.objects[2] };
    moveObject(l, 2, fuel.x, fuel.y - 20, true, d);
    expect(l.objects[2]).toEqual(fuel);
    moveObject(l, 2, fuel.x, fuel.y - 20, false, d);
    expect(l.objects[2].y).toBe(fuel.y - 20);
  });

  it('added fuel goes before guns; pod stand goes first', () => {
    const l = level(0); // pod, generator, fuel, gun
    const d = decodeLevel(l);
    expect(addObject(l, 4, 0x30, 0x190, d)).toBe(3);
    expect(l.objects.map((o) => o.type)).toEqual([5, 6, 4, 4, 0]);
    expect(addObject(l, 5, 0x60, 0x190, d)).toBe(0);
    // the new fuel (now index 4) snapped down onto the surface at row $1aa
    expect(l.objects[4]).toEqual({ type: 4, x: 0x30, y: 0x1aa - 10 + 3, gun: 0 });
  });

  it('sortObjects: pod, generator, fuel, then the rest in their order', () => {
    const l = level(2);
    l.objects.reverse();
    const guns = l.objects.filter((o) => o.type < 4);
    sortObjects(l);
    expect(l.objects.slice(0, 8).map((o) => o.type)).toEqual([5, 6, 4, 4, 4, 4, 4, 4]);
    expect(l.objects.slice(8)).toEqual(guns);
  });
});

describe('restart ops', () => {
  it('window moves with the ship', () => {
    const l = level(2);
    const r = { ...l.restarts[1] };
    moveRestart(l, 1, r.shipX + 5, r.shipY + 10);
    expect(l.restarts[1]).toEqual({ shipX: r.shipX + 5, shipY: r.shipY + 10, windowX: r.windowX + 5, windowY: r.windowY + 10 });
  });

  it('added restart points stay in depth order; the start is never removed', () => {
    const l = level(2); // ship Y $191, $22d, $296
    expect(addRestart(l, 0x80, 0x250)).toBe(2);
    expect(l.restarts[2]).toEqual({ shipX: 0x80, shipY: 0x250, windowX: 0x80 - 0x16, windowY: 0x250 - 0x64 });
    expect(addRestart(l, 0x80, 0x100)).toBe(1); // never before the start
    expect(deleteRestart(l, 0)).toBe(false);
  });
});

import { fillDoor } from '../src/editor/ops';

describe('door ops', () => {
  it('fill passage: rows meet the other wall, a slide door opens back to its own wall', () => {
    const l = level(0);
    const d = decodeLevel(l, 0x400);
    const top = 0x240;
    l.door = { side: 'right', top, mode: 'slide', rows: [0x80, 0x80, 0x80], max: 4, openX: 0, time: 0xff };
    expect(fillDoor(l, d)).toBe(true);
    l.door.rows.forEach((x, k) => expect(x).toBe(d.left[top + k] - 1));
    expect(l.door.max).toBe(Math.max(...l.door.rows.map((x, k) => d.right[top + k] - x)));
    expect(fillDoor(l, d)).toBe(false);
  });
});
