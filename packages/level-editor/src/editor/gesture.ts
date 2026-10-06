// Touch gestures, as pure functions (input.ts does the events).

export interface Pt {
  x: number;
  y: number;
}

/** A finger that moves less than this (px) is a tap or a hold, not a drag. */
export const TAP_SLOP = 8;
/** Holding a wall line this long (ms) adds a point there. */
export const LONG_PRESS_MS = 450;
/** Hit radius (px) for a finger and for a mouse or pen. */
export const TOUCH_HIT = 22;
export const MOUSE_HIT = 8;

/** Has a finger moved far enough from where it went down to be a drag? */
export const isDrag = (start: Pt, now: Pt): boolean => Math.hypot(now.x - start.x, now.y - start.y) > TAP_SLOP;

/** One step of a two-finger gesture: fingers moved from (a0, b0) to (a1, b1).
 *  Zoom by `zoom` about (cx, cy) (the new midpoint), after panning by (dx, dy)
 *  (how far the midpoint moved). */
export function pinchStep(a0: Pt, b0: Pt, a1: Pt, b1: Pt): { zoom: number; dx: number; dy: number; cx: number; cy: number } {
  const d0 = Math.hypot(b0.x - a0.x, b0.y - a0.y);
  const d1 = Math.hypot(b1.x - a1.x, b1.y - a1.y);
  const cx = (a1.x + b1.x) / 2;
  const cy = (a1.y + b1.y) / 2;
  return {
    zoom: d0 > 0 && d1 > 0 ? d1 / d0 : 1,
    dx: cx - (a0.x + b0.x) / 2,
    dy: cy - (a0.y + b0.y) / 2,
    cx,
    cy,
  };
}

/** Where the loupe goes for a finger at (x, y) in a w x h view: above the
 *  finger, to the side away from the nearer edge, kept inside the view. */
export function loupeCentre(x: number, y: number, w: number, h: number, radius: number): Pt {
  const gap = radius + 36;
  const cx = x > w / 2 ? x - gap * 0.7 : x + gap * 0.7;
  const cy = y - gap;
  const m = radius + 4;
  return {
    x: Math.min(w - m, Math.max(m, cx)),
    y: cy < m ? Math.min(h - m, y + gap) : Math.min(h - m, cy),
  };
}
