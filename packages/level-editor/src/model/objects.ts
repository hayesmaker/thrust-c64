// Objects on the terrain: snapping, gun firing arcs.

import { OBJ_SIZE, type LevelObject } from './level';

/** Is world cell (x, row) rock? `left`/`right` are decoded wall X per row
 *  (past the end, the last row repeats). Same rule as the game's drawing. */
export function isSolid(left: number[], right: number[], x: number, row: number): boolean {
  if (row < 0) return false;
  const r = Math.min(row, left.length - 1);
  const l = left[r];
  const rr = right[r];
  x &= 0xff;
  return l < rr ? x < l || x > rr : true;
}

/** How each type sits on the terrain, measured from the original levels
 *  (every original object matches its rule):
 *  floor: first rock row below the object = y + height + gap
 *  ceil:  last rock row above the object's bottom = y - 1 - gap
 *  left/right: wall on that side, `gap` units away. */
type SnapRule = { kind: 'floor' | 'ceil' | 'left' | 'right'; gap: number };
export const SNAP: SnapRule[] = [
  { kind: 'floor', gap: -4 }, // gun up-right
  { kind: 'ceil', gap: -4 }, // gun down-right
  { kind: 'floor', gap: -3 }, // gun up-left
  { kind: 'ceil', gap: -3 }, // gun down-left
  { kind: 'floor', gap: -3 }, // fuel
  { kind: 'floor', gap: 2 }, // pod stand
  { kind: 'floor', gap: -1 }, // generator
  { kind: 'left', gap: 0 }, // door switch R (wall on its left)
  { kind: 'right', gap: 1 }, // door switch L (wall on its right)
];

const SEARCH = 160;

/** Position of `o` snapped to the terrain, or null if there is nothing to
 *  rest on within reach. Searches from the object's current place. */
export function snapObject(o: LevelObject, left: number[], right: number[]): { x: number; y: number } | null {
  const rule = SNAP[o.type];
  if (!rule) return null;
  const [w, h] = OBJ_SIZE[o.type];
  const rowSolid = (row: number) => {
    for (let c = 0; c < w; c++) if (isSolid(left, right, o.x + c, row)) return true;
    return false;
  };
  const colSolid = (x: number) => {
    for (let j = 0; j < h; j++) if (isSolid(left, right, x, o.y + j)) return true;
    return false;
  };
  switch (rule.kind) {
    case 'floor': {
      // start in free space at the top of the object (climb out of rock)
      let r = o.y;
      for (let k = 0; k < SEARCH && rowSolid(r); k++) r--;
      for (let k = 0; k < SEARCH; k++, r++) if (rowSolid(r)) return { x: o.x, y: r - h - rule.gap };
      return null;
    }
    case 'ceil': {
      let r = o.y + h - 1;
      for (let k = 0; k < SEARCH && rowSolid(r); k++) r++;
      for (let k = 0; k < SEARCH && r >= 0; k++, r--) if (rowSolid(r)) return { x: o.x, y: r + 1 + rule.gap };
      return null;
    }
    case 'left': {
      let c = o.x;
      for (let k = 0; k < 128 && colSolid(c); k++) c++;
      for (let k = 0; k < 128; k++, c--) if (colSolid(c)) return { x: (c + 1 + rule.gap) & 0xff, y: o.y };
      return null;
    }
    case 'right': {
      let c = o.x + w - 1;
      for (let k = 0; k < 128 && colSolid(c); k++) c--;
      for (let k = 0; k < 128; k++, c++) if (colSolid(c)) return { x: (c - w - rule.gap) & 0xff, y: o.y };
      return null;
    }
  }
}

// ---- guns ------------------------------------------------------------------

export const isGun = (type: number) => type >= 0 && type <= 3;

/** Spread masks indexed by gun param bits 0-1 (gun_param_table). */
export const GUN_SPREAD = [1, 3, 7, 15];
/** Bullet start offset from the object's top-left (gun_bullet_x/y_offset). */
export const GUN_MUZZLE: [number, number][] = [
  [4, 0],
  [4, 8],
  [1, 0],
  [1, 8],
];
export const ANGLE_NAMES = ['up', 'up-right', 'right', 'down-right', 'down', 'down-left', 'left', 'up-left'];

export const gunBase = (param: number) => param & 0x1c;
export const gunSpread = (param: number) => param & 0x03;
export const gunParam = (base: number, spread: number, old = 0) => (old & 0xe0) | (base & 0x1c) | (spread & 0x03);

/** Firing directions (0-31, 0 = up, 8 = right): the game fires at
 *  base + (rnd & mask) + (rnd & 3), so from base to base + mask + 3. */
export function gunArc(param: number): { from: number; to: number } {
  const from = gunBase(param);
  return { from, to: from + GUN_SPREAD[gunSpread(param)] + 3 };
}
