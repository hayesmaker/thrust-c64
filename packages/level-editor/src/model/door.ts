// Doors and level rules: the level_door_* / level_rule_* / round_cycle_* tables
// in level_tables.asm and the level_N_door_x shapes in levels.asm, as read by
// tick_door_logic and apply_level_rules in the mod's thrust.asm.

import { upgradeTitle } from './title';

export type DoorSide = 'left' | 'right';
export type DoorMode = 'slide' | 'reveal';

/** One door per level, opened by any door switch on the level. */
export interface Door {
  side: DoorSide;
  /** world Y of the first door row */
  top: number;
  mode: DoorMode;
  /** closed wall X per door row (4-pixel units) */
  rows: number[];
  /** max opening: X units (slide) or rows (reveal) */
  max: number;
  /** reveal: wall X of the opened rows */
  openX: number;
  /** switch counter start value: open time in ticks (about 255 - 2 * max open) */
  time: number;
}

/** 0 follow round, 1 on, 2 off, 3 invert round (level_rule_* values). */
export const RULES = ['round', 'on', 'off', 'invert'] as const;
export type Rule = (typeof RULES)[number];

export interface LevelRules {
  reverse: Rule;
  invisible: Rule;
}

export interface Round {
  reverse: boolean;
  invisible: boolean;
}

export const MAX_DOOR_ROWS = 200;
export const MAX_ROUNDS = 8;
export const MODE_RIGHT = 0x80;
export const MODE_REVEAL = 0x40;

export const defaultRules = (): LevelRules => ({ reverse: 'round', invisible: 'round' });

/** The original game: normal, reverse, invisible, reverse + invisible. */
export const defaultRoundCycle = (): Round[] => [
  { reverse: false, invisible: false },
  { reverse: true, invisible: false },
  { reverse: false, invisible: true },
  { reverse: true, invisible: true },
];

/** The original game's doors (levels 3, 4, 5; all on the left wall). */
export const ORIGINAL_DOORS: Record<number, Door> = {
  3: { side: 'left', top: 0x269, mode: 'slide', rows: new Array(13).fill(0xae), max: 0x10, openX: 0, time: 0xff },
  4: { side: 'left', top: 0x344, mode: 'reveal', rows: new Array(21).fill(0xa6), max: 0x15, openX: 0x98, time: 0xff },
  5: {
    side: 'left',
    top: 0x370,
    mode: 'slide',
    rows: [...Array.from({ length: 7 }, (_, k) => 0xc0 + k), ...Array.from({ length: 8 }, (_, k) => 0xc7 - k)],
    max: 0x12,
    openX: 0,
    time: 0xff,
  },
};

export const cloneDoor = (d: Door): Door => ({ ...d, rows: d.rows.slice() });

/** A new door: `rows` rows at `top`, closed at the given wall X values. */
export function newDoor(side: DoorSide, top: number, rows: number[]): Door {
  return { side, top, mode: 'slide', rows, max: 0x10, openX: 0, time: 0xff };
}

/** Wall X per door row at opening `b` (what tick_door_logic writes). */
export function doorWallX(d: Door, b: number): number[] {
  return d.rows.map((x, i) => {
    if (d.mode === 'reveal') return i < b ? d.openX : x;
    return (d.side === 'left' ? x - b : x + b) & 0xff;
  });
}

/** The opening amount over time after the switch is shot (counter A from
 *  `time`, counter B follows), one value per tick until closed again. */
export function doorTimeline(d: Door): number[] {
  let a = d.time;
  let b = 0;
  const out: number[] = [];
  for (let t = 0; t < 600; t++) {
    if (a) a--;
    if (a < d.max) b = a;
    else if (b < d.max) b++;
    out.push(b);
    if (a === 0 && b === 0) break;
  }
  return out;
}

export function modeByte(d: Door | null): number {
  if (!d) return 0;
  return (d.side === 'right' ? MODE_RIGHT : 0) | (d.mode === 'reveal' ? MODE_REVEAL : 0);
}

// ---- asm text for sources that predate doors as data -----------------------

const hex = (v: number) => '$' + (v & 0xff).toString(16).padStart(2, '0');
const bytes = (vs: number[]) => `    .byte ${vs.map(hex).join(',')}`;
const per = (f: (n: number) => number) => bytes([0, 1, 2, 3, 4, 5].map(f));

/** level_tables.asm blocks (inserted after level_gravity_FRAC_table). */
export function doorTablesAsm(doors: (Door | null)[] = [0, 1, 2, 3, 4, 5].map((n) => ORIGINAL_DOORS[n] ?? null)): string {
  const ptr = (op: string) =>
    `    .byte ${[0, 1, 2, 3, 4, 5].map((n) => `${op}(level_${n}_door_x)`).join(',')}`;
  const cyc = defaultRoundCycle();
  return [
    '// ----------------------------------------------------------------------------',
    '// Doors: at most one per level, opened by any door switch (object type 7/8) on it.',
    '// Rows 0 = no door. Mode bit7: right wall (else left), bit6: reveal (else slide).',
    '// slide:  wall X = closed X - opening (left wall) or + opening (right wall)',
    '// reveal: the top <opening> rows are level_door_open_x, the rest closed X',
    '// Closed X per row: level_N_door_x in levels.asm.',
    '// ----------------------------------------------------------------------------',
    'level_door_rows:',
    per((n) => doors[n]?.rows.length ?? 0),
    'level_door_top_LO:',
    per((n) => doors[n]?.top ?? 0),
    'level_door_top_HI:',
    per((n) => (doors[n]?.top ?? 0) >> 8),
    'level_door_mode:',
    per((n) => modeByte(doors[n])),
    'level_door_max:',
    per((n) => doors[n]?.max ?? 0),
    'level_door_open_x:',
    per((n) => doors[n]?.openX ?? 0),
    'level_door_time:',
    per((n) => doors[n]?.time ?? 0xff),
    'level_door_shape_LO:',
    ptr('<'),
    'level_door_shape_HI:',
    ptr('>'),
    '// ----------------------------------------------------------------------------',
    '// Rules: reverse gravity / invisible landscape. Each round (one pass through all',
    '// levels) uses the next round_cycle_* entry ($00 off, $ff on); a level rule then',
    '// changes it: 0 follow round, 1 on, 2 off, 3 invert round.',
    '// ----------------------------------------------------------------------------',
    'level_rule_reverse:',
    per(() => 0),
    'level_rule_invisible:',
    per(() => 0),
    'round_cycle_reverse:',
    bytes(cyc.map((r) => (r.reverse ? 0xff : 0))),
    'round_cycle_invisible:',
    bytes(cyc.map((r) => (r.invisible ? 0xff : 0))),
    'round_cycle_end:',
    '    .errorif round_cycle_end - round_cycle_invisible != round_cycle_invisible - round_cycle_reverse, "round_cycle_reverse and round_cycle_invisible must have the same length"',
  ].join('\n');
}

/** levels.asm blocks (appended at the end). */
export function doorShapesAsm(doors: (Door | null)[] = [0, 1, 2, 3, 4, 5].map((n) => ORIGINAL_DOORS[n] ?? null)): string {
  const out = ['// Door shapes: closed wall X per door row (see level_door_* in level_tables.asm)'];
  for (let n = 0; n < 6; n++) out.push(`level_${n}_door_x:`, bytes(doors[n]?.rows.length ? doors[n]!.rows : [0]));
  return out.join('\n');
}

/** Add the door / rule tables and the title line to level sources made
 *  before they were there. Sources that have them are returned unchanged. */
export function upgradeSources(levelsAsm: string, tablesAsm: string): { levelsAsm: string; tablesAsm: string } {
  const has = (s: string, label: string) => new RegExp(`^${label}:`, 'm').test(s);
  const eol = (s: string) => (s.includes('\r\n') ? '\r\n' : '\n');
  if (!has(tablesAsm, 'level_door_rows')) {
    const e = eol(tablesAsm);
    const lines = tablesAsm.split(/\r?\n/);
    const at = lines.findIndex((l) => /^level_gravity_FRAC_table:/.test(l));
    if (at < 0) throw new Error('level_tables.asm: level_gravity_FRAC_table not found');
    let end = at + 1;
    while (end < lines.length && /^\s*\.byte\b/.test(lines[end])) end++;
    lines.splice(end, 0, ...doorTablesAsm().split('\n'));
    tablesAsm = lines.join(e);
  }
  tablesAsm = upgradeTitle(tablesAsm);
  if (!has(levelsAsm, 'level_0_door_x')) {
    const e = eol(levelsAsm);
    const body = levelsAsm.replace(/(\r?\n)*$/, '');
    levelsAsm = body + e + doorShapesAsm().split('\n').join(e) + e;
  }
  return { levelsAsm, tablesAsm };
}
