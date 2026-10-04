// Level checks (rules from docs/level_format.md) and the memory budget.

import { type Level, OBJ_NAMES, ObjType, decodeLevel, levelRows, wallTables } from './level';
import { isSolid, snapObject } from './objects';

export type Severity = 'error' | 'warn' | 'info';

export type Target =
  | { kind: 'object'; index: number }
  | { kind: 'restart'; index: number }
  | { kind: 'wall'; side: 'left' | 'right' };

export interface Issue {
  level: number;
  severity: Severity;
  message: string;
  target?: Target;
}

export const MAX_OBJECTS = 32;
export const FUEL_SLOTS = 12;
export const MAX_ENTRIES = 255;

/** Doors are code (tick_door_logic), not data: top row and rows per level. */
export const DOORS: Record<number, { top: number; xs: number[] }> = {
  3: { top: 0x269, xs: new Array(13).fill(0xae) },
  4: { top: 0x344, xs: new Array(21).fill(0xa6) },
  5: {
    top: 0x370,
    xs: [...Array.from({ length: 7 }, (_, k) => 0xc0 + k), ...Array.from({ length: 8 }, (_, k) => 0xc7 - k)],
  },
};

export function validateLevel(l: Level): Issue[] {
  const out: Issue[] = [];
  const add = (severity: Severity, message: string, target?: Target) =>
    out.push({ level: l.index, severity, message, target });
  const { left, right } = decodeLevel(l, levelRows(l, 64));
  const o = l.objects;

  // objects
  if (o.length > MAX_OBJECTS) add('error', `${o.length} objects: the limit is ${MAX_OBJECTS}`);
  if (o[0]?.type !== ObjType.PodStand) add('error', 'object 0 must be the pod stand', o.length ? { kind: 'object', index: 0 } : undefined);
  const pods = o.filter((v) => v.type === ObjType.PodStand).length;
  if (pods > 1) add('warn', `${pods} pod stands: only object 0 is used for the pod`);
  if (!o.some((v) => v.type === ObjType.Generator)) add('warn', 'no generator (reactor)');
  o.forEach((v, i) => {
    const t: Target = { kind: 'object', index: i };
    if (v.type > 8) return add('error', `object ${i}: unknown type ${v.type}`, t);
    if (v.type === ObjType.Fuel && i >= FUEL_SLOTS)
      add('error', `object ${i} (fuel) must be among the first ${FUEL_SLOTS} objects`, t);
    if (v.y < 0 || v.y > 0xffff) add('error', `object ${i}: Y out of range`, t);
    const s = snapObject(v, left, right);
    if (!s) add('warn', `object ${i} (${OBJ_NAMES[v.type]}) has no terrain to rest on`, t);
    else if (s.x !== v.x || s.y !== v.y)
      add('info', `object ${i} (${OBJ_NAMES[v.type]}) is not resting on the terrain`, t);
  });

  // restart points
  const r = l.restarts;
  if (r.length === 0) add('error', 'at least one restart point (the start) is needed');
  r.forEach((p, i) => {
    const t: Target = { kind: 'restart', index: i };
    if (i > 0 && p.shipY < r[i - 1].shipY)
      add('warn', `restart ${i} is above restart ${i - 1}: they should go down in order`, t);
    if (isSolid(left, right, p.shipX, p.shipY)) add('warn', `restart ${i}: ship starts inside rock`, t);
  });

  // terrain
  for (const side of ['left', 'right'] as const) {
    const n = wallTables(l[side]).counts.length;
    if (n > MAX_ENTRIES) add('error', `${side} wall: ${n} table entries (max ${MAX_ENTRIES})`, { kind: 'wall', side });
  }
  const last = left.length - 1;
  if (left[last] < right[last]) add('warn', 'the cave is open at the bottom (the walls never meet)');

  if (DOORS[l.index])
    add('info', `level ${l.index} has a hard-coded door at row $${DOORS[l.index].top.toString(16)} (orange): keep the left wall there`);
  if (o.some((v) => v.gun & 0xe0)) add('info', 'some gun parameters use bits 5-7 (ignored by the game)');
  return out;
}

// ---- memory -------------------------------------------------------------------
//
// Rough budgets (the build has the exact check: .errorif in thrust.asm).
// Original game: terrain 434 + objects 356 bytes (levels.asm) and 102 bytes of
// restart tables (level_tables.asm), all in the main block, which had 348
// bytes free at $BEA4-$BFFF. thrusty-levels moves levels.asm to its own area
// ($1000-$1FFF), which also frees its 790 bytes in the main block.

export const ORIGINAL_LEVELS_ASM_BYTES = 790;
export const ORIGINAL_RESTART_BYTES = 102;
export const ORIGINAL_LEVEL_BYTES = ORIGINAL_LEVELS_ASM_BYTES + ORIGINAL_RESTART_BYTES;
export const FREE_MAIN_BYTES = 348;
export const LEVEL_BUDGET = ORIGINAL_LEVEL_BYTES + FREE_MAIN_BYTES;
/** "tight" below this many free bytes or 10% of the area, whichever is more */
export const TIGHT_BYTES = 64;

export interface Layout {
  levelsArea: { start: number; end: number } | null;
}

export type MemState = 'ok' | 'tight' | 'over';

export interface MemArea {
  id: 'levels' | 'main';
  label: string;
  used: number;
  budget: number;
  free: number;
  state: MemState;
}

export function levelBytes(l: Level): { terrain: number; objects: number; restarts: number; total: number } {
  const terrain = 2 * (wallTables(l.left).counts.length + wallTables(l.right).counts.length);
  const objects = 5 * l.objects.length + 1;
  const restarts = 6 * l.restarts.length;
  return { terrain, objects, restarts, total: terrain + objects + restarts };
}

const area = (id: MemArea['id'], label: string, used: number, budget: number): MemArea => {
  const free = budget - used;
  const state: MemState = free < 0 ? 'over' : free < Math.max(TIGHT_BYTES, budget * 0.1) ? 'tight' : 'ok';
  return { id, label, used, budget, free, state };
};

/** Where the level data goes and roughly how full each place is. */
export function memoryAreas(levels: Level[], layout: Layout | null): MemArea[] {
  const sum = (f: (b: ReturnType<typeof levelBytes>) => number) => levels.reduce((n, l) => n + f(levelBytes(l)), 0);
  const la = layout?.levelsArea;
  if (!la) return [area('main', 'level data (main block, ends below $C000)', sum((b) => b.total), LEVEL_BUDGET)];
  const hex = (v: number) => '$' + v.toString(16).toUpperCase();
  return [
    area('levels', `terrain + objects (levels area ${hex(la.start)}-${hex(la.end - 1)})`, sum((b) => b.terrain + b.objects), la.end - la.start),
    // the main block keeps its free bytes plus the 790 that levels.asm used to take
    area('main', 'restart points (main block, ends below $C000)', sum((b) => b.restarts),
      ORIGINAL_RESTART_BYTES + FREE_MAIN_BYTES + ORIGINAL_LEVELS_ASM_BYTES),
  ];
}

export const worstState = (areas: MemArea[]): MemState =>
  areas.some((a) => a.state === 'over') ? 'over' : areas.some((a) => a.state === 'tight') ? 'tight' : 'ok';

/** Checks entries for the memory areas (project-wide). */
export function memoryIssues(areas: MemArea[], level: number): Issue[] {
  return areas
    .filter((a) => a.state !== 'ok')
    .map((a) => ({
      level,
      severity: a.state === 'over' ? ('error' as const) : ('warn' as const),
      message:
        a.state === 'over'
          ? `out of memory: ${a.label} is ${-a.free} bytes over (${a.used} of ~${a.budget}); the build will fail`
          : `memory is tight: ${a.free} bytes left for ${a.label}`,
    }));
}
