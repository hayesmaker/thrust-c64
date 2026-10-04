// Level project: the 6 levels read from levels.asm + level_tables.asm, and
// written back by patching only the tables that changed.

import { type AsmDoc, type AsmValue, blockBytes, blockValues, parseAsm, serializeAsm, writeBlock } from './asm';
import {
  LEFT_START_X,
  RIGHT_START_X,
  type Point,
  type WallTables,
  decodeWall,
  encodeWall,
  importWall,
  wallRows,
} from './terrain';

export const LEVEL_COUNT = 6;

export enum ObjType {
  GunUpRight = 0,
  GunDownRight = 1,
  GunUpLeft = 2,
  GunDownLeft = 3,
  Fuel = 4,
  PodStand = 5,
  Generator = 6,
  SwitchRight = 7,
  SwitchLeft = 8,
}

export const OBJ_NAMES = [
  'gun up-right',
  'gun down-right',
  'gun up-left',
  'gun down-left',
  'fuel',
  'pod stand',
  'generator',
  'door switch R',
  'door switch L',
];
/** obj_type_width / obj_type_height (X units, rows). */
export const OBJ_SIZE: [number, number][] = [
  [5, 8], [5, 8], [5, 8], [5, 8], [4, 10], [5, 8], [5, 10], [2, 8], [2, 8],
];

export interface LevelObject {
  type: number;
  x: number;
  y: number; // 16-bit world Y
  gun: number;
}

export interface RestartPoint {
  shipX: number;
  shipY: number;
  windowX: number;
  windowY: number;
}

export const COLOUR_KEYS = ['terrain', 'mc1', 'mc3', 'status', 'objects', 'shield'] as const;
export type ColourKey = (typeof COLOUR_KEYS)[number];
export type Colours = Record<ColourKey, number>;

export interface Wall {
  start: number;
  points: Point[];
  /** Tables as read from the source; dropped when the wall is edited so the
   *  file is only rewritten for walls that actually changed. */
  raw?: WallTables;
}

export interface Level {
  index: number;
  left: Wall;
  right: Wall;
  objects: LevelObject[];
  restarts: RestartPoint[];
  gravity: number;
  colours: Colours;
}

export interface Project {
  levels: Level[];
  /** The source files as loaded; saveProject patches fresh copies of them. */
  levelsAsm: string;
  tablesAsm: string;
}

export function wallTables(w: Wall): WallTables {
  return w.raw ?? encodeWall(w.points);
}

/** Mark a wall as edited (after changing its points). */
export function touchWall(w: Wall): void {
  delete w.raw;
}

/** Rows to show/decode for a level: until both walls stop changing, plus a margin. */
export function levelRows(l: Level, margin = 32): number {
  return Math.max(wallRows(wallTables(l.left)), wallRows(wallTables(l.right))) + margin;
}

export function decodeLevel(l: Level, rows = levelRows(l)): { left: number[]; right: number[] } {
  return {
    left: decodeWall(wallTables(l.left), l.left.start, rows),
    right: decodeWall(wallTables(l.right), l.right.start, rows),
  };
}

const T = (n: number, s: string) => `terrain_data_level_${n}_${s}`;
const O = (n: number, s: string) => `level_${n}_${s}`;

function readWall(doc: AsmDoc, n: number, c: string, s: string, start: number): Wall {
  const raw = { counts: blockBytes(doc, T(n, c)), steps: blockBytes(doc, T(n, s)) };
  return { start, raw, points: importWall(raw, start) };
}

export function loadProject(levelsAsm: string, tablesAsm: string): Project {
  const levelsDoc = parseAsm(levelsAsm);
  const tablesDoc = parseAsm(tablesAsm);
  const sizes = blockBytes(tablesDoc, 'level_reset_data_sizes');
  const gravity = blockBytes(tablesDoc, 'level_gravity_FRAC_table');
  const colourTabs = Object.fromEntries(
    COLOUR_KEYS.map((k) => [k, blockBytes(tablesDoc, `level_colour_${k}`)]),
  ) as Record<ColourKey, number[]>;

  const levels: Level[] = [];
  for (let n = 0; n < LEVEL_COUNT; n++) {
    const xs = blockBytes(levelsDoc, O(n, 'obj_pos_X'));
    const ys = blockBytes(levelsDoc, O(n, 'obj_pos_Y'));
    const yes = blockBytes(levelsDoc, O(n, 'obj_pos_Y_EXT'));
    const types = blockBytes(levelsDoc, O(n, 'obj_type'));
    const guns = blockBytes(levelsDoc, O(n, 'gun_param'));
    const objects: LevelObject[] = [];
    for (let i = 0; i < types.length && types[i] !== 0xff; i++)
      objects.push({ type: types[i], x: xs[i], y: yes[i] * 256 + ys[i], gun: guns[i] });

    const k = sizes[n];
    const rd = blockBytes(tablesDoc, O(n, 'reset_data'));
    const restarts: RestartPoint[] = [];
    for (let i = 0; i < k; i++) {
      const v = (row: number) => rd[row * k + i];
      restarts.push({ shipY: v(0) * 256 + v(1), windowX: v(2), windowY: v(3) * 256 + v(4), shipX: v(5) });
    }

    levels.push({
      index: n,
      left: readWall(levelsDoc, n, 'A', 'B', LEFT_START_X),
      right: readWall(levelsDoc, n, 'C', 'D', RIGHT_START_X),
      objects,
      restarts,
      gravity: gravity[n],
      colours: Object.fromEntries(COLOUR_KEYS.map((c) => [c, colourTabs[c][n]])) as Colours,
    });
  }
  return { levels, levelsAsm, tablesAsm };
}

/** Write every level into copies of the loaded sources; returns the new sources. */
export function saveProject(p: Project): { levelsAsm: string; tablesAsm: string } {
  const L = parseAsm(p.levelsAsm);
  const Tb = parseAsm(p.tablesAsm);
  for (const l of p.levels) {
    const n = l.index;
    for (const [w, c, s] of [
      [l.left, 'A', 'B'],
      [l.right, 'C', 'D'],
    ] as const) {
      if (w.raw) continue; // unedited: keep the source exactly as it was
      const t = encodeWall(w.points);
      writeBlock(L, T(n, c), t.counts);
      writeBlock(L, T(n, s), t.steps);
    }
    const o = l.objects;
    writeBlock(L, O(n, 'obj_pos_X'), o.map((v) => v.x & 0xff));
    writeBlock(L, O(n, 'obj_pos_Y'), o.map((v) => v.y & 0xff));
    writeBlock(L, O(n, 'obj_pos_Y_EXT'), o.map((v) => (v.y >> 8) & 0xff));
    writeBlock(L, O(n, 'obj_type'), [...o.map((v) => v.type), 0xff]);
    writeBlock(L, O(n, 'gun_param'), o.map((v) => v.gun));

    const r = l.restarts;
    const k = r.length;
    const rows = [
      r.map((v) => v.shipY >> 8),
      r.map((v) => v.shipY & 0xff),
      r.map((v) => v.windowX),
      r.map((v) => v.windowY >> 8),
      r.map((v) => v.windowY & 0xff),
      r.map((v) => v.shipX),
    ].flat();
    // same count: keep the line layout; new count: one line per row
    const oldK = blockBytes(Tb, 'level_reset_data_sizes')[n];
    writeBlock(Tb, O(n, 'reset_data'), rows, oldK === k ? {} : { perLine: k });
    setAt(Tb, 'level_reset_data_sizes', n, k);
    setAt(Tb, 'level_reset_ptr2_table_LO', n, `<(level_${n}_reset_data+${k})`);
    setAt(Tb, 'level_reset_ptr2_table_HI', n, `>(level_${n}_reset_data+${k})`);
    setAt(Tb, 'level_gravity_FRAC_table', n, l.gravity);
    for (const c of COLOUR_KEYS) setAt(Tb, `level_colour_${c}`, n, l.colours[c]);
  }
  return { levelsAsm: serializeAsm(L), tablesAsm: serializeAsm(Tb) };
}

function setAt(doc: AsmDoc, label: string, i: number, v: AsmValue): void {
  const vals = blockValues(doc, label).slice();
  vals[i] = v;
  writeBlock(doc, label, vals);
}
