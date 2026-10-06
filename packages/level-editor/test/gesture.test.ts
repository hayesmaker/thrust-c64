import { describe, expect, it } from 'vitest';
import { TAP_SLOP, isDrag, loupeCentre, pinchStep } from '../src/editor/gesture';

describe('touch gestures', () => {
  it('a finger that stays within the slop is a tap, not a drag', () => {
    expect(isDrag({ x: 100, y: 100 }, { x: 100 + TAP_SLOP - 1, y: 100 })).toBe(false);
    expect(isDrag({ x: 100, y: 100 }, { x: 100, y: 100 + TAP_SLOP + 1 })).toBe(true);
  });

  it('pinch: spreading the fingers to twice the distance zooms x2 about the midpoint', () => {
    const s = pinchStep({ x: 90, y: 100 }, { x: 110, y: 100 }, { x: 80, y: 100 }, { x: 120, y: 100 });
    expect(s.zoom).toBeCloseTo(2);
    expect(s).toMatchObject({ dx: 0, dy: 0, cx: 100, cy: 100 });
  });

  it('pinch: moving both fingers together pans without zooming', () => {
    const s = pinchStep({ x: 0, y: 0 }, { x: 50, y: 0 }, { x: 10, y: 30 }, { x: 60, y: 30 });
    expect(s.zoom).toBeCloseTo(1);
    expect(s).toMatchObject({ dx: 10, dy: 30, cx: 35, cy: 30 });
  });

  it('pinch: fingers on the same spot do not zoom', () => {
    expect(pinchStep({ x: 5, y: 5 }, { x: 5, y: 5 }, { x: 5, y: 5 }, { x: 9, y: 5 }).zoom).toBe(1);
  });

  it('the loupe sits above the finger, inside the view, away from the nearer edge', () => {
    const r = 60;
    const mid = loupeCentre(200, 300, 800, 600, r);
    expect(mid.y).toBeLessThan(300);
    expect(mid.x).toBeGreaterThan(200); // left half: to the right
    const right = loupeCentre(700, 300, 800, 600, r);
    expect(right.x).toBeLessThan(700);
    const top = loupeCentre(400, 20, 800, 600, r); // no room above: below
    expect(top.y).toBeGreaterThan(20);
    for (const p of [mid, right, top]) {
      expect(p.x - r).toBeGreaterThanOrEqual(0);
      expect(p.y + r).toBeLessThanOrEqual(600);
    }
  });
});
