// Mouse and keyboard: drag points/objects/restart points, insert on lines,
// pan, zoom, shortcuts.
//
//   drag point            move it (Shift: lock to a whole step per row)
//   click/drag on a line  insert a point there
//   drag object           move it; it snaps to the terrain (Alt: free)
//   drag restart cross    move the ship start; its screen window follows
//   drag door tab         move the door (Shift: sideways only)
//   drag door row handle  move that row's closed edge (Shift: all rows)
//   right-click / Del     delete what is under the mouse / selected
//   drag empty space      pan            wheel: scroll, Ctrl+wheel: zoom
//   arrows                nudge selected (Shift: x8)
//   Ctrl+Z / Ctrl+Shift+Z undo / redo    F: fit level   1-6: level
//
// Touch (pointerType "touch"; the mouse and pen work as above):
//   tap                   select (tap empty space: deselect)
//   drag                  move what is under the finger, relative to where it
//                         was grabbed (no jump); a loupe shows the spot
//   drag empty space      pan            two fingers: pan + pinch zoom
//   hold a wall line      add a point there (then drag it)
//   touch toolbar         Step / Free stand in for Shift / Alt (TouchMods)

import {
  deleteDoor,
  deleteDoorRow,
  deleteObject,
  deletePoint,
  deleteRestart,
  insertPoint,
  moveDoor,
  moveDoorRow,
  moveObject,
  movePoint,
  moveRestart,
} from './ops';
import { LONG_PRESS_MS, MOUSE_HIT, type Pt, TOUCH_HIT, isDrag, pinchStep } from './gesture';
import { type Selection, type Store, sameSelection } from './store';
import { type View } from './view';

/** The touch toolbar's stand-ins for Shift (step) and Alt (free). */
export interface TouchMods {
  step: boolean;
  free: boolean;
}

type Drag =
  | { kind: 'point'; side: 'left' | 'right'; index: number; tile: number }
  | { kind: 'object'; index: number; tile: number; grabX: number; grabY: number }
  | { kind: 'restart'; index: number; tile: number }
  | { kind: 'door'; index: number; tile: number; startX: number; startRow: number; top: number; rows: number[] }
  | { kind: 'pan'; lastX: number; lastY: number; moved: boolean };

/** Delete the selected point/object/restart point. */
export function deleteSelection(store: Store): void {
  const l = store.current;
  const sel = store.selection;
  if (!l || !sel) return;
  store.checkpoint();
  const ok =
    sel.kind === 'point'
      ? deletePoint(l[sel.side], sel.index)
      : sel.kind === 'object'
        ? deleteObject(l, sel.index)
        : sel.kind === 'door'
          ? sel.index < 0
            ? deleteDoor(l)
            : deleteDoorRow(l, sel.index)
          : deleteRestart(l, sel.index);
  if (!ok) return store.cancelCheckpointIfUnchanged();
  store.selection = null;
  if (sel.kind === 'point') store.terrainChanged();
  else store.changed();
}

/** Move the selection by (dx, drow); objects keep the snap setting. */
export function nudgeSelection(store: Store, dx: number, dr: number, snap: boolean): void {
  const l = store.current;
  const sel = store.selection;
  if (!l || !sel) return;
  store.checkpoint();
  let ok = false;
  if (sel.kind === 'point') {
    const p = l[sel.side].points[sel.index];
    ok = movePoint(l[sel.side], sel.index, p.row + dr, p.x + dx);
  } else if (sel.kind === 'object') {
    const o = l.objects[sel.index];
    // snapping would undo a vertical nudge of a floor object, so nudge freely
    ok = moveObject(l, sel.index, o.x + dx, o.y + dr, snap && dr === 0 && dx !== 0, store.decoded);
  } else if (sel.kind === 'door') {
    const d = l.door;
    if (d && sel.index >= 0) ok = (dx !== 0 && moveDoorRow(l, sel.index, d.rows[sel.index] + dx)) || (dr !== 0 && moveDoor(l, d.top + dr, 0));
    else if (d) ok = moveDoor(l, d.top + dr, dx);
  } else {
    const r = l.restarts[sel.index];
    ok = moveRestart(l, sel.index, r.shipX + dx, r.shipY + dr);
  }
  if (!ok) store.cancelCheckpointIfUnchanged();
  else if (sel.kind === 'point') store.terrainChanged();
  else store.changed();
}

export function attachInput(
  view: View,
  store: Store,
  mods: TouchMods = { step: false, free: false },
  onTouchMode: (on: boolean) => void = () => {},
): void {
  const canvas = view.canvas;
  let drag: Drag | null = null;

  /** Finger or mouse: bigger hit areas and handles, and the touch toolbar. */
  const setTouchMode = (on: boolean) => {
    view.hitRadius = on ? TOUCH_HIT : MOUSE_HIT;
    if (view.touchMode === on) return;
    view.touchMode = on;
    onTouchMode(on);
    view.requestDraw();
  };

  /** Keep getting a pointer's events outside the canvas (not possible for a
   *  pointer that is already gone, or a synthetic one). */
  const capture = (id: number) => {
    try {
      canvas.setPointerCapture(id);
    } catch {
      // ignore
    }
  };

  const pos = (e: MouseEvent) => {
    const r = canvas.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  };

  /** What is under the mouse, in priority order. */
  const hitAny = (x: number, y: number) => {
    const p = view.hitPoint(x, y);
    if (p) return { sel: { kind: 'point', side: p.side, index: p.index } as Selection, tile: p.tile, grab: null };
    const d = view.hitDoor(x, y);
    if (d) return { sel: { kind: 'door', index: d.index } as Selection, tile: d.tile, grab: null };
    const r = view.hitRestart(x, y);
    if (r) return { sel: { kind: 'restart', index: r.index } as Selection, tile: r.tile, grab: null };
    const o = view.hitObject(x, y);
    if (o) return { sel: { kind: 'object', index: o.index } as Selection, tile: o.tile, grab: { x: o.grabX, y: o.grabY } };
    return null;
  };

  /** Move the dragged thing to world position `w` (shift / alt: the modifiers). */
  const applyDrag = (d: Exclude<Drag, { kind: 'pan' }>, w: { x: number; row: number }, shift: boolean, alt: boolean) => {
    const l = store.current;
    if (!l) return;
    let ok = false;
    if (d.kind === 'point') ok = movePoint(l[d.side], d.index, w.row, w.x - d.tile, shift);
    else if (d.kind === 'object') {
      const snap = store.snapObjects !== alt;
      ok = moveObject(l, d.index, w.x - d.tile - d.grabX, w.row - d.grabY, snap, store.decoded);
    } else if (d.kind === 'door' && l.door) {
      const dx = Math.round(w.x - d.startX);
      const dr = Math.round(w.row - d.startRow);
      const before = JSON.stringify(l.door);
      if (d.index < 0) {
        // the whole door; Shift: sideways only
        l.door.rows = d.rows.slice();
        l.door.top = d.top;
        moveDoor(l, shift ? d.top : d.top + dr, dx);
      } else if (shift) {
        l.door.rows = d.rows.slice();
        moveDoor(l, l.door.top, dx);
      } else {
        l.door.rows = d.rows.slice();
        moveDoorRow(l, d.index, d.rows[d.index] + dx);
      }
      ok = JSON.stringify(l.door) !== before;
    } else if (d.kind === 'restart') ok = moveRestart(l, d.index, w.x - d.tile, w.row);
    if (ok && d.kind === 'point') store.terrainChanged();
    else if (ok) store.changed();
  };

  /** The drag for a hit (as a mouse press starts it), at world position w. */
  const dragFor = (hit: NonNullable<ReturnType<typeof hitAny>>, w: { x: number; row: number }): Exclude<Drag, { kind: 'pan' }> => {
    const s = hit.sel;
    const l = store.current!;
    return s.kind === 'point'
      ? { kind: 'point', side: s.side, index: s.index, tile: hit.tile }
      : s.kind === 'object'
        ? { kind: 'object', index: s.index, tile: hit.tile, grabX: hit.grab!.x, grabY: hit.grab!.y }
        : s.kind === 'door'
          ? { kind: 'door', index: s.index, tile: hit.tile, startX: w.x, startRow: w.row, top: l.door!.top, rows: l.door!.rows.slice() }
          : { kind: 'restart', index: s.index, tile: hit.tile };
  };

  canvas.addEventListener('contextmenu', (e) => e.preventDefault());

  canvas.addEventListener('pointerdown', (e) => {
    if (e.pointerType === 'touch') return touchDown(e);
    setTouchMode(false);
    const l = store.current;
    if (!l) return;
    const p = pos(e);
    capture(e.pointerId);

    if (e.button === 2) {
      const hit = hitAny(p.x, p.y);
      if (hit) {
        store.selection = hit.sel;
        deleteSelection(store);
      }
      return;
    }
    if (e.button === 1) {
      drag = { kind: 'pan', lastX: p.x, lastY: p.y, moved: false };
      return;
    }

    const hit = hitAny(p.x, p.y);
    if (hit) {
      store.checkpoint();
      store.selection = hit.sel;
      drag = dragFor(hit, view.toWorld(p.x, p.y));
      store.changed(false);
      return;
    }
    const seg = view.hitSegment(p.x, p.y);
    if (seg) {
      store.checkpoint();
      if (insertPoint(l[seg.side], seg.index, seg.row, seg.x)) {
        store.selection = { kind: 'point', side: seg.side, index: seg.index };
        drag = { kind: 'point', side: seg.side, index: seg.index, tile: seg.tile };
        store.terrainChanged();
        return;
      }
      store.cancelCheckpointIfUnchanged();
    }
    drag = { kind: 'pan', lastX: p.x, lastY: p.y, moved: false };
  });

  canvas.addEventListener('pointermove', (e) => {
    if (e.pointerType === 'touch') return touchMove(e);
    if (e.pointerType === 'mouse') setTouchMode(false);
    const p = pos(e);
    const w = view.toWorld(p.x, p.y);
    view.cursor = w;
    const l = store.current;
    if (drag?.kind === 'pan') {
      view.pan(p.x - drag.lastX, p.y - drag.lastY);
      drag.moved ||= p.x !== drag.lastX || p.y !== drag.lastY;
      drag.lastX = p.x;
      drag.lastY = p.y;
    } else if (drag && l) {
      applyDrag(drag, w, e.shiftKey, e.altKey);
    } else {
      const hit = hitAny(p.x, p.y);
      const next = hit?.sel ?? null;
      if (!sameSelection(next, store.hover) && (next || store.hover)) {
        store.hover = next;
        view.requestDraw();
      }
      canvas.style.cursor = hit ? 'grab' : view.hitSegment(p.x, p.y) ? 'copy' : 'default';
    }
    view.requestDraw();
    statusUpdate();
  });

  const end = () => {
    if (drag && drag.kind !== 'pan') store.cancelCheckpointIfUnchanged();
    if (drag?.kind === 'pan' && !drag.moved && store.selection) {
      store.selection = null;
      store.changed(false);
    }
    drag = null;
  };
  canvas.addEventListener('pointerup', (e) => (e.pointerType === 'touch' ? touchUp(e) : end()));
  canvas.addEventListener('pointercancel', (e) => (e.pointerType === 'touch' ? touchUp(e) : end()));
  canvas.addEventListener('pointerleave', (e) => {
    if (e.pointerType === 'touch') return;
    view.cursor = null;
    view.requestDraw();
  });

  // ---- touch -------------------------------------------------------------

  /** What is under a finger: the nearest thing (the bigger radius reaches
   *  several), ties going by the mouse's priority order. */
  const hitTouch = (x: number, y: number): ReturnType<typeof hitAny> => {
    const cands: { d: number; hit: NonNullable<ReturnType<typeof hitAny>> }[] = [];
    const p = view.hitPoint(x, y);
    if (p) cands.push({ d: p.d, hit: { sel: { kind: 'point', side: p.side, index: p.index }, tile: p.tile, grab: null } });
    const d = view.hitDoor(x, y);
    if (d) cands.push({ d: d.d + 1, hit: { sel: { kind: 'door', index: d.index }, tile: d.tile, grab: null } });
    const r = view.hitRestart(x, y);
    if (r) cands.push({ d: r.d + 2, hit: { sel: { kind: 'restart', index: r.index }, tile: r.tile, grab: null } });
    const o = view.hitObject(x, y);
    if (o) cands.push({ d: o.d + 3, hit: { sel: { kind: 'object', index: o.index }, tile: o.tile, grab: { x: o.grabX, y: o.grabY } } });
    cands.sort((a, b) => a.d - b.d);
    return cands[0]?.hit ?? null;
  };

  const fingers = new Map<number, Pt>();
  /** The one-finger gesture: pending (tap or hold) until it moves. */
  let t: {
    id: number;
    start: Pt;
    last: Pt;
    hit: ReturnType<typeof hitAny>;
    seg: ReturnType<View['hitSegment']>;
    mode: 'pending' | 'drag' | 'pan';
    timer: number;
    drag: Exclude<Drag, { kind: 'pan' }> | null;
    /** world position of the finger, and of the dragged point / restart, when the drag began */
    w0: { x: number; row: number };
    origin: { x: number; row: number } | null;
  } | null = null;
  let pinch: { a: Pt; b: Pt } | null = null;
  /** After a pinch, fingers do nothing until all are lifted. */
  let settled = false;

  const startTouchDrag = (hit: NonNullable<ReturnType<typeof hitAny>>) => {
    const l = store.current;
    if (!t || !l) return;
    store.checkpoint();
    store.selection = hit.sel;
    // from where the finger went down, so the slop doesn't make it jump
    t.w0 = view.toWorld(t.start.x, t.start.y);
    t.drag = dragFor(hit, t.w0);
    const s = hit.sel;
    t.origin =
      s.kind === 'point'
        ? { x: l[s.side].points[s.index].x, row: l[s.side].points[s.index].row }
        : s.kind === 'restart'
          ? { x: l.restarts[s.index].shipX, row: l.restarts[s.index].shipY }
          : null;
    t.mode = 'drag';
    store.changed(false);
  };

  const longPress = () => {
    const l = store.current;
    if (!t || t.mode !== 'pending' || !t.seg || !l) return;
    const seg = t.seg;
    store.checkpoint();
    if (!insertPoint(l[seg.side], seg.index, seg.row, seg.x)) return store.cancelCheckpointIfUnchanged();
    store.selection = { kind: 'point', side: seg.side, index: seg.index };
    navigator.vibrate?.(10);
    t.mode = 'drag';
    t.drag = { kind: 'point', side: seg.side, index: seg.index, tile: seg.tile };
    t.w0 = view.toWorld(t.last.x, t.last.y);
    t.origin = { x: seg.x, row: seg.row };
    view.loupe = { sx: t.last.x, sy: t.last.y, x: seg.x + seg.tile, row: seg.row };
    store.terrainChanged();
  };

  function touchDown(e: PointerEvent): void {
    setTouchMode(true);
    if (!store.current) return;
    capture(e.pointerId);
    const p = pos(e);
    fingers.set(e.pointerId, p);
    if (fingers.size === 2) {
      // a second finger: pan / zoom; undo whatever the first one started
      if (t) {
        clearTimeout(t.timer);
        if (t.mode === 'drag') store.abandonCheckpoint();
      }
      t = null;
      view.loupe = null;
      const [a, b] = [...fingers.values()];
      pinch = { a, b };
      settled = true;
      view.requestDraw();
      return;
    }
    if (fingers.size > 1 || settled) return;
    const hit = hitTouch(p.x, p.y);
    const seg = hit ? null : view.hitSegment(p.x, p.y);
    t = { id: e.pointerId, start: p, last: p, hit, seg, mode: 'pending', timer: 0, drag: null, w0: view.toWorld(p.x, p.y), origin: null };
    if (seg) t.timer = window.setTimeout(longPress, LONG_PRESS_MS);
  }

  function touchMove(e: PointerEvent): void {
    const prev = fingers.get(e.pointerId);
    if (!prev) return;
    const p = pos(e);
    fingers.set(e.pointerId, p);
    if (pinch) {
      const [a, b] = [...fingers.values()];
      const s = pinchStep(pinch.a, pinch.b, a, b);
      view.pan(s.dx, s.dy);
      view.zoomAt(s.cx, s.cy, s.zoom);
      pinch = { a, b };
      return;
    }
    if (!t || t.id !== e.pointerId) return;
    t.last = p;
    if (t.mode === 'pending') {
      if (!isDrag(t.start, p)) return;
      clearTimeout(t.timer);
      if (t.hit) startTouchDrag(t.hit);
      else t.mode = 'pan';
    }
    if (t.mode === 'pan') {
      view.pan(p.x - prev.x, p.y - prev.y);
      return;
    }
    if (!t.drag) return;
    // relative: the thing moves as far as the finger did, from where it was
    const w = view.toWorld(p.x, p.y);
    const target = t.origin ? { x: t.origin.x + t.drag.tile + (w.x - t.w0.x), row: t.origin.row + (w.row - t.w0.row) } : w;
    applyDrag(t.drag, target, mods.step, mods.free);
    view.cursor = target;
    // magnify the point or restart where it ended up (moves snap to whole units)
    const l = store.current!;
    const d = t.drag;
    const at =
      d.kind === 'point'
        ? { x: l[d.side].points[d.index].x + d.tile, row: l[d.side].points[d.index].row }
        : d.kind === 'restart'
          ? { x: l.restarts[d.index].shipX + d.tile, row: l.restarts[d.index].shipY }
          : w;
    view.loupe = { sx: p.x, sy: p.y, x: at.x, row: at.row };
    view.requestDraw();
    statusUpdate();
  }

  function touchUp(e: PointerEvent): void {
    fingers.delete(e.pointerId);
    if (pinch && fingers.size < 2) pinch = null;
    if (fingers.size === 0) settled = false;
    if (!t || t.id !== e.pointerId) return;
    clearTimeout(t.timer);
    if (t.mode === 'pending' && e.type === 'pointerup') {
      // a tap: select what is there, or deselect
      if (t.hit) {
        store.selection = t.hit.sel;
        store.changed(false);
      } else if (store.selection) {
        store.selection = null;
        store.changed(false);
      }
    } else if (t.mode === 'drag') store.cancelCheckpointIfUnchanged();
    t = null;
    view.loupe = null;
    view.cursor = null;
    view.requestDraw();
  }

  canvas.addEventListener(
    'wheel',
    (e) => {
      e.preventDefault();
      const p = pos(e);
      if (e.ctrlKey || e.metaKey) view.zoomAt(p.x, p.y, Math.exp(-e.deltaY * 0.002));
      else if (e.shiftKey) view.pan(-e.deltaY, 0);
      else view.pan(-e.deltaX, -e.deltaY);
    },
    { passive: false },
  );

  window.addEventListener('keydown', (e) => {
    const t = e.target as HTMLElement;
    if (t.tagName === 'INPUT' || t.tagName === 'SELECT' || t.tagName === 'TEXTAREA') return;
    if (!store.current || store.inputPaused) return;
    const mod = e.ctrlKey || e.metaKey;
    if (mod && e.key.toLowerCase() === 'z') {
      e.preventDefault();
      if (e.shiftKey) store.redo();
      else store.undo();
      return;
    }
    if (mod && e.key.toLowerCase() === 'y') {
      e.preventDefault();
      store.redo();
      return;
    }
    if (mod) return;
    const sel = store.selection;
    if (sel && (e.key === 'Delete' || e.key === 'Backspace')) {
      e.preventDefault();
      deleteSelection(store);
      return;
    }
    const nudge: Record<string, [number, number]> = {
      ArrowLeft: [-1, 0],
      ArrowRight: [1, 0],
      ArrowUp: [0, -1],
      ArrowDown: [0, 1],
    };
    if (sel && nudge[e.key]) {
      e.preventDefault();
      const k = e.shiftKey ? 8 : 1;
      nudgeSelection(store, nudge[e.key][0] * k, nudge[e.key][1] * k, store.snapObjects);
      return;
    }
    if (e.key === 'f' || e.key === 'F') view.fitLevel();
    if (e.key === '+' || e.key === '=') view.zoomAt(canvas.clientWidth / 2, canvas.clientHeight / 2, 1.25);
    if (e.key === '-') view.zoomAt(canvas.clientWidth / 2, canvas.clientHeight / 2, 0.8);
    if (e.key === 'Escape' && sel) {
      store.selection = null;
      store.changed(false);
    }
    if (/^[1-6]$/.test(e.key)) {
      store.setLevel(Number(e.key) - 1);
      view.fitLevel();
    }
  });

  const status = document.getElementById('status');
  function statusUpdate() {
    if (!status) return;
    const c = view.cursor;
    if (!c) return;
    const x = Math.floor(c.x) & 0xff;
    const r = Math.floor(c.row);
    status.textContent =
      `X $${x.toString(16).padStart(2, '0')} (${x})   row $${Math.max(0, r).toString(16).padStart(3, '0')} (${r})` +
      `   zoom ${view.scale.toFixed(2)} px/row`;
  }
}
