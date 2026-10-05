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
import { type Selection, type Store, sameSelection } from './store';
import { type View } from './view';

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

export function attachInput(view: View, store: Store): void {
  const canvas = view.canvas;
  let drag: Drag | null = null;

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

  canvas.addEventListener('contextmenu', (e) => e.preventDefault());

  canvas.addEventListener('pointerdown', (e) => {
    const l = store.current;
    if (!l) return;
    const p = pos(e);
    canvas.setPointerCapture(e.pointerId);

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
      const s = hit.sel;
      const w = view.toWorld(p.x, p.y);
      drag =
        s.kind === 'point'
          ? { kind: 'point', side: s.side, index: s.index, tile: hit.tile }
          : s.kind === 'object'
            ? { kind: 'object', index: s.index, tile: hit.tile, grabX: hit.grab!.x, grabY: hit.grab!.y }
            : s.kind === 'door'
              ? { kind: 'door', index: s.index, tile: hit.tile, startX: w.x, startRow: w.row, top: l.door!.top, rows: l.door!.rows.slice() }
              : { kind: 'restart', index: s.index, tile: hit.tile };
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
      let ok = false;
      if (drag.kind === 'point') ok = movePoint(l[drag.side], drag.index, w.row, w.x - drag.tile, e.shiftKey);
      else if (drag.kind === 'object') {
        const snap = store.snapObjects !== e.altKey;
        ok = moveObject(l, drag.index, w.x - drag.tile - drag.grabX, w.row - drag.grabY, snap, store.decoded);
      } else if (drag.kind === 'door' && l.door) {
        const dx = Math.round(w.x - drag.startX);
        const dr = Math.round(w.row - drag.startRow);
        const before = JSON.stringify(l.door);
        if (drag.index < 0) {
          // the whole door; Shift: sideways only
          l.door.rows = drag.rows.slice();
          l.door.top = drag.top;
          moveDoor(l, e.shiftKey ? drag.top : drag.top + dr, dx);
        } else if (e.shiftKey) {
          l.door.rows = drag.rows.slice();
          moveDoor(l, l.door.top, dx);
        } else {
          l.door.rows = drag.rows.slice();
          moveDoorRow(l, drag.index, drag.rows[drag.index] + dx);
        }
        ok = JSON.stringify(l.door) !== before;
      } else if (drag.kind === 'restart') ok = moveRestart(l, drag.index, w.x - drag.tile, w.row);
      if (ok && drag.kind === 'point') store.terrainChanged();
      else if (ok) store.changed();
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
  canvas.addEventListener('pointerup', end);
  canvas.addEventListener('pointercancel', end);
  canvas.addEventListener('pointerleave', () => {
    view.cursor = null;
    view.requestDraw();
  });

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
