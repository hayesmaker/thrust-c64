import { describe, expect, it } from 'vitest';
import { ORIGINAL_DOORS, doorTimeline, doorWallX } from '../src/model/door';

// Ports of the original game's per-level door routines (tick_door_logic before
// doors were data): wall X per row from the door top, at opening b.
const ORIGINAL_ROUTINES: Record<number, (b: number) => number[]> = {
  // 13 rows at $269: $AE - b
  3: (b) => new Array(13).fill((0xae - b) & 0xff),
  // rows $344-$358 (old top $343 + 1..21): counting up from the bottom, row y
  // switches to $98 once y == b, so the top b rows are open
  4: (b) => {
    const out = new Array(22).fill(0);
    let a = 0xa6;
    for (let y = 0x15; y > 0; y--) {
      if (y === b) a = 0x98;
      out[y] = a;
    }
    return out.slice(1);
  },
  // diamond at $370: 7 rows $C0..$C6, then 8 rows $C7..$C0, all - b
  5: (b) => {
    const out: number[] = [];
    let a = (0xc0 - b) & 0xff;
    for (let k = 0; k < 7; k++) out.push(a++);
    for (let k = 0; k < 8; k++) out.push(a--);
    return out;
  },
};

describe('doorWallX', () => {
  it.each([3, 4, 5])('level %i matches the original routine at every opening', (n) => {
    const d = ORIGINAL_DOORS[n];
    for (let b = 0; b <= d.max; b++) expect(doorWallX(d, b)).toEqual(ORIGINAL_ROUTINES[n](b));
  });

  it('a right wall door slides right', () => {
    const d = { ...ORIGINAL_DOORS[3], side: 'right' as const, rows: [0x40, 0x50] };
    expect(doorWallX(d, 5)).toEqual([0x45, 0x55]);
  });
});

describe('doorTimeline', () => {
  it('opens one step per tick, stays open, then closes as the counter runs out', () => {
    const d = ORIGINAL_DOORS[3];
    const t = doorTimeline(d);
    expect(t.slice(0, 17)).toEqual(Array.from({ length: 17 }, (_, i) => Math.min(i + 1, 0x10)));
    expect(t[t.length - 1]).toBe(0);
    expect(t.filter((b) => b === d.max).length).toBeGreaterThan(200);
  });
});
