// Touch toolbar over the canvas: what the keyboard and mouse buttons do on a
// desktop. Shown while editing by touch (and on coarse-pointer screens from
// the start); hidden again as soon as a mouse moves over the canvas.
//
//   Undo / Redo / Fit / zoom - +       always
//   nudge pad, x8, Delete              with a selection (arrow keys, Shift, Del)
//   Step                               points and door: Shift while dragging
//   Free                               objects: Alt while dragging (no snapping)

import { type TouchMods, deleteSelection, nudgeSelection } from './input';
import { type Store } from './store';
import { type View } from './view';

const REPEAT_DELAY = 400;
const REPEAT_EVERY = 90;

export interface Touchbar {
  setVisible(on: boolean): void;
  /** Call after store changes (selection, undo history). */
  update(): void;
}

export function mountTouchbar(stage: HTMLElement, store: Store, view: View, mods: TouchMods): Touchbar {
  const bar = document.createElement('div');
  bar.id = 'touchbar';
  if (matchMedia('(pointer: coarse)').matches) bar.classList.add('show');
  bar.innerHTML = `
    <div class="group">
      <button data-a="undo" title="Undo">↶</button>
      <button data-a="redo" title="Redo">↷</button>
      <button data-a="fit" title="Fit the level">Fit</button>
      <button data-a="out" title="Zoom out">−</button>
      <button data-a="in" title="Zoom in">+</button>
    </div>
    <div class="group sel">
      <button data-n="-1,0" title="Nudge left">←</button>
      <button data-n="0,-1" title="Nudge up">↑</button>
      <button data-n="0,1" title="Nudge down">↓</button>
      <button data-n="1,0" title="Nudge right">→</button>
      <button data-t="big" title="Nudge 8 at a time (Shift)">×8</button>
      <button data-t="step" class="for-point for-door" title="Points: whole step per row. Door: sideways only (Shift)">Step</button>
      <button data-t="free" class="for-object" title="Objects don't snap to the terrain (Alt)">Free</button>
      <button data-a="delete" class="danger" title="Delete (Del)">Delete</button>
    </div>`;
  stage.appendChild(bar);
  let big = false;

  const centre = () => ({ x: view.canvas.clientWidth / 2, y: view.canvas.clientHeight / 2 });
  const actions: Record<string, () => void> = {
    undo: () => store.undo(),
    redo: () => store.redo(),
    fit: () => view.fitLevel(),
    out: () => view.zoomAt(centre().x, centre().y, 0.8),
    in: () => view.zoomAt(centre().x, centre().y, 1.25),
    delete: () => deleteSelection(store),
  };

  // keep taps on the bar from reaching the canvas or zooming the page
  bar.addEventListener('pointerdown', (e) => e.stopPropagation());
  bar.addEventListener('dblclick', (e) => e.preventDefault());

  for (const b of bar.querySelectorAll<HTMLButtonElement>('button[data-a]')) b.onclick = () => actions[b.dataset.a!]();

  for (const b of bar.querySelectorAll<HTMLButtonElement>('button[data-t]'))
    b.onclick = () => {
      const k = b.dataset.t!;
      if (k === 'big') big = !big;
      else mods[k as keyof TouchMods] = !mods[k as keyof TouchMods];
      update();
    };

  // nudges repeat while held
  for (const b of bar.querySelectorAll<HTMLButtonElement>('button[data-n]')) {
    const [dx, dr] = b.dataset.n!.split(',').map(Number);
    let timer = 0;
    const step = () => nudgeSelection(store, dx * (big ? 8 : 1), dr * (big ? 8 : 1), store.snapObjects !== mods.free);
    const stop = () => clearTimeout(timer);
    b.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      step();
      const again = () => {
        step();
        timer = window.setTimeout(again, REPEAT_EVERY);
      };
      timer = window.setTimeout(again, REPEAT_DELAY);
    });
    for (const ev of ['pointerup', 'pointercancel', 'pointerleave']) b.addEventListener(ev, stop);
  }

  function update(): void {
    const sel = store.selection;
    bar.classList.toggle('has-sel', !!sel);
    for (const b of bar.querySelectorAll<HTMLElement>('.for-point, .for-door, .for-object')) {
      const fits = !!sel && b.classList.contains(`for-${sel.kind}`);
      b.hidden = !fits;
    }
    const on = (k: string, v: boolean) => bar.querySelector(`[data-t="${k}"]`)!.classList.toggle('on', v);
    on('big', big);
    on('step', mods.step);
    on('free', mods.free);
    (bar.querySelector('[data-a="undo"]') as HTMLButtonElement).disabled = !store.canUndo();
    (bar.querySelector('[data-a="redo"]') as HTMLButtonElement).disabled = !store.canRedo();
  }
  update();

  return {
    setVisible: (on) => bar.classList.toggle('show', on),
    update,
  };
}
