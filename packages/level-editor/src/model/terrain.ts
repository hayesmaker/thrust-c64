// Terrain walls: the game's run-length tables <-> editable points.
//
// A wall is two parallel tables (see docs/level_format.md):
//   counts[i] = run length in rows, steps[i] = X added on every row of the run.
// The decoder starts at entry 1 with an implicit count of $FF (255 rows), so
// entry 0 is a dummy and entry 1's count is never read. From entry 2 on, a
// count of $FF ends the wall (X stays put from then on); a count of 0 means
// 256 rows. X is 8 bits and wraps.
//
// The editor keeps a wall as points {row, x}: xs[row] === x (mod 256), with X
// unwrapped (a sum of signed steps) so a wall that wraps stays continuous.
// points[0] is the fixed anchor at the end of the sky run (row 254).

export interface WallTables {
  counts: number[];
  steps: number[];
}

export interface Point {
  row: number;
  x: number;
}

export const LEFT_START_X = 0x00;
export const RIGHT_START_X = 0xff;
/** Rows covered by entry 1 (the sky run). */
export const SKY_ROWS = 255;
/** Row of points[0]: the last sky row. */
export const ANCHOR_ROW = SKY_ROWS - 1;
/** Longest run one entry can hold ($FF would end the wall). */
export const MAX_RUN = 254;

export const signed8 = (v: number): number => ((v & 0xff) ^ 0x80) - 0x80;
export const mod256 = (v: number): number => v & 0xff;

/** Exact model of the game's decoder (terrain_accumulate_xpos_fn), as in
 *  tools/levelview.py: wall X (0-255) after each of the first `rows` rows. */
export function decodeWall(t: WallTables, startX: number, rows: number): number[] {
  let x = startX;
  let c = 0xff;
  let i = 1;
  let ended = false;
  const xs: number[] = new Array(rows);
  for (let row = 0; row < rows; row++) {
    if (c === 0 && !ended) {
      i++;
      c = t.counts[i] ?? 0xff;
      ended = c === 0xff;
    }
    if (!ended) x = (x + (t.steps[i] ?? 0)) & 0xff;
    c = (c - 1) & 0xff;
    xs[row] = x;
  }
  return xs;
}

/** Number of rows until the wall stops changing (the $FF terminator). */
export function wallRows(t: WallTables): number {
  let n = SKY_ROWS;
  for (let i = 2; i < t.counts.length && t.counts[i] !== 0xff; i++) n += t.counts[i] || 256;
  return n;
}

/** Per-row steps for a straight segment of `dy` rows changing X by `dx`.
 *  Uneven segments put the larger steps first in each group, so a steep slope
 *  becomes "1 row of ±1, k rows of 0" like the original staircases. */
export function segmentSteps(dy: number, dx: number): number[] {
  const m = Math.abs(dx);
  const sign = dx < 0 ? -1 : 1;
  const ceilDiv = (a: number) => Math.floor((a + dy - 1) / dy);
  const out: number[] = new Array(dy);
  for (let j = 1; j <= dy; j++) out[j - 1] = sign * (ceilDiv(j * m) - ceilDiv((j - 1) * m)) || 0; // no -0
  return out;
}

export interface Run {
  rows: number;
  step: number; // signed
}

/** Points -> runs (merged, split to MAX_RUN), excluding the sky entry. */
export function pointsToRuns(points: Point[]): Run[] {
  checkPoints(points);
  const runs: Run[] = [];
  for (let k = 1; k < points.length; k++) {
    const a = points[k - 1];
    const b = points[k];
    for (const s of segmentSteps(b.row - a.row, b.x - a.x)) {
      const last = runs[runs.length - 1];
      if (last && last.step === s && last.rows < MAX_RUN) last.rows++;
      else runs.push({ rows: 1, step: s });
    }
  }
  return runs;
}

/** Points -> game tables (dummy entry, sky entry, runs, $FF terminator). */
export function encodeWall(points: Point[]): WallTables {
  const runs = pointsToRuns(points);
  return {
    counts: [0xff, 0xff, ...runs.map((r) => r.rows), 0xff],
    steps: [0x00, 0x00, ...runs.map((r) => mod256(r.step)), 0x00],
  };
}

export function checkPoints(points: Point[]): void {
  if (points.length === 0 || points[0].row !== ANCHOR_ROW)
    throw new Error(`wall must start with the anchor point at row ${ANCHOR_ROW}`);
  for (let k = 1; k < points.length; k++)
    if (points[k].row <= points[k - 1].row)
      throw new Error(`wall point ${k} (row ${points[k].row}) is not below point ${k - 1}`);
}

/** Tables -> one point per run boundary (exact, unsimplified). */
export function tablesToPoints(t: WallTables, startX: number): Point[] {
  if (t.steps[1] !== 0) throw new Error('sky run with a non-zero step is not supported');
  const pts: Point[] = [{ row: ANCHOR_ROW, x: startX }];
  let row = ANCHOR_ROW;
  let x = startX;
  for (let i = 2; i < t.counts.length && t.counts[i] !== 0xff; i++) {
    const n = t.counts[i] || 256;
    row += n;
    x += n * signed8(t.steps[i]);
    pts.push({ row, x });
  }
  return pts;
}

/** Unwrapped X on every row from the anchor to the last point. */
function rowXs(points: Point[]): number[] {
  const xs = [points[0].x];
  for (let k = 1; k < points.length; k++) {
    let x = points[k - 1].x;
    for (const s of segmentSteps(points[k].row - points[k - 1].row, points[k].x - points[k - 1].x)) {
      x += s;
      xs.push(x);
    }
  }
  return xs;
}

/** Drop points where a straight segment gives exactly the same rows
 *  (e.g. a staircase becomes one steep line). The result decodes identically. */
export function simplifyPoints(points: Point[]): Point[] {
  const xs = rowXs(points);
  const base = points[0].row;
  const fits = (a: Point, b: Point) => {
    let x = a.x;
    let row = a.row;
    for (const s of segmentSteps(b.row - a.row, b.x - a.x)) {
      x += s;
      row++;
      if (xs[row - base] !== x) return false;
    }
    return true;
  };
  const out = [points[0]];
  let i = 0;
  while (i < points.length - 1) {
    let j = i + 1;
    while (j + 1 < points.length && fits(points[i], points[j + 1])) j++;
    out.push(points[j]);
    i = j;
  }
  return out;
}

export function importWall(t: WallTables, startX: number): Point[] {
  return simplifyPoints(tablesToPoints(t, startX));
}
