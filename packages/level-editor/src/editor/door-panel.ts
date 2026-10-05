// Side panel sections for the level's door and the rules (reverse gravity,
// invisible landscape per level, and the game's round cycle).

import { hex2, hex3 } from '../c64';
import { type DoorMode, type DoorSide, MAX_DOOR_ROWS, MAX_ROUNDS, RULES, type Rule, defaultRoundCycle, doorTimeline } from '../model/door';
import { type Level, ObjType } from '../model/level';
import { addDoorRow, createDoor, deleteDoor, deleteDoorRow, fillDoor, traceDoor } from './ops';
import { type Store } from './store';
import { type View } from './view';

const RULE_LABELS: Record<Rule, string> = {
  round: 'follow the round',
  on: 'always on',
  off: 'always off',
  invert: 'opposite of the round',
};

export const DOOR_HTML = `
  <details open>
    <summary>Door <span class="muted" id="d-sum"></span></summary>
    <div id="d-none">
      <div class="muted small">No door on this level. A door is opened by shooting any door switch (objects 7 and 8) on the level.</div>
      <div class="row">
        <button id="d-add-left" title="a door on the left wall at the centre of the view">Add door, left wall</button>
        <button id="d-add-right" title="a door on the right wall at the centre of the view">Add door, right wall</button>
      </div>
    </div>
    <div id="d-edit">
      <div class="grid2">
        <label>wall <select id="d-side"><option value="left">left</option><option value="right">right</option></select></label>
        <label>mode <select id="d-mode"><option value="slide">slide</option><option value="reveal">reveal</option></select></label>
        <label>top row <input type="number" id="d-top" min="0" max="65535"></label>
        <label>rows <input type="number" id="d-rows" min="1" max="${MAX_DOOR_ROWS}"></label>
        <label><span id="d-max-label">max opening</span> <input type="number" id="d-max" min="0" max="255"></label>
        <label id="d-openx-box">open X <input type="number" id="d-openx" min="0" max="255"></label>
        <label>open time <input type="number" id="d-time" min="1" max="255"></label>
      </div>
      <label>preview <input type="range" id="d-preview" min="0" max="16" value="0"> <span class="muted" id="d-preview-v"></span></label>
      <div class="muted small" id="d-info"></div>
      <div class="row">
        <button id="d-trace" title="set every row's closed edge to the terrain wall plus the depth">Trace from wall</button>
        <label class="inline">depth <input type="number" id="d-depth" min="1" max="255" value="16" style="width:4em"></label>
      </div>
      <div class="row">
        <button id="d-fill" title="every row reaches the opposite wall; a slide door's max opening is set so it opens back to its own wall">Fill passage</button>
      </div>
      <label>closed X per row <textarea id="d-xs" rows="3" spellcheck="false"></textarea></label>
      <div class="row"><button id="d-del">Delete door</button></div>
    </div>
  </details>`;

export const RULES_HTML = `
  <details>
    <summary>Rules <span class="muted" id="r-sum"></span></summary>
    <label>reverse gravity <select id="r-rev">${RULES.map((r) => `<option value="${r}">${RULE_LABELS[r]}</option>`).join('')}</select></label>
    <label>invisible landscape <select id="r-inv">${RULES.map((r) => `<option value="${r}">${RULE_LABELS[r]}</option>`).join('')}</select></label>
    <div class="muted small" id="r-level-info"></div>
    <div class="table-head">Round cycle (whole game): each pass through the 6 levels is one round</div>
    <ul class="rounds" id="r-rounds"></ul>
    <div class="row">
      <button id="r-add" title="add a round to the cycle">Add round</button>
      <button id="r-reset" title="normal, reverse, invisible, reverse + invisible">Original cycle</button>
    </div>
  </details>`;

const flagText = (rev: boolean, inv: boolean) =>
  rev && inv ? 'reverse + invisible' : rev ? 'reverse' : inv ? 'invisible' : 'normal';

/** What a level rule makes of a round's flag. */
export function applyRule(rule: Rule, round: boolean): boolean {
  return rule === 'round' ? round : rule === 'on' ? true : rule === 'off' ? false : !round;
}

type Edit = (fn: (l: Level) => boolean | void, terrain?: boolean) => void;

export function mountDoorRules(root: HTMLElement, store: Store, view: View, edit: Edit): (l: Level) => void {
  const $ = <T extends HTMLElement = HTMLElement>(id: string) => root.querySelector<T>('#' + id)!;
  const num = (id: string) => Number($<HTMLInputElement>(id).value);
  const byte = (v: number) => Math.max(0, Math.min(255, Math.round(v) || 0));
  const viewCentreRow = () => Math.round(view.toWorld(0, view.canvas.clientHeight / 2).row);

  // ---- door
  const add = (side: DoorSide) =>
    edit((l) => {
      createDoor(l, side, viewCentreRow(), 12, num('d-depth') || 16, store.decoded);
      store.selection = { kind: 'door', index: -1 };
      store.doorPreview = 0;
    });
  $('d-add-left').onclick = () => add('left');
  $('d-add-right').onclick = () => add('right');
  $('d-del').onclick = () => edit((l) => deleteDoor(l));
  $<HTMLSelectElement>('d-side').onchange = (e) =>
    edit((l) => {
      if (!l.door) return false;
      l.door.side = (e.target as HTMLSelectElement).value as DoorSide;
      traceDoor(l, l.door.mode === 'slide' ? l.door.max : num('d-depth') || 16, store.decoded);
    });
  $<HTMLSelectElement>('d-mode').onchange = (e) =>
    edit((l) => {
      const d = l.door;
      if (!d) return false;
      d.mode = (e.target as HTMLSelectElement).value as DoorMode;
      if (d.mode === 'reveal') {
        d.max = Math.min(d.max, d.rows.length);
        if (!d.openX) {
          const wall = store.decoded[d.side];
          d.openX = byte(wall[Math.min(d.top, wall.length - 1)] ?? 0);
        }
      }
    });
  $('d-top').onchange = () =>
    edit((l) => {
      if (!l.door) return false;
      l.door.top = Math.max(0, Math.min(0xffff, num('d-top') | 0));
    });
  $('d-rows').onchange = () =>
    edit((l) => {
      const d = l.door;
      if (!d) return false;
      const n = Math.max(1, Math.min(MAX_DOOR_ROWS, num('d-rows') | 0));
      while (d.rows.length < n) addDoorRow(l);
      while (d.rows.length > n) deleteDoorRow(l, d.rows.length - 1);
    });
  $('d-max').onchange = () =>
    edit((l) => {
      const d = l.door;
      if (!d) return false;
      d.max = byte(num('d-max'));
      if (d.mode === 'reveal') d.max = Math.min(d.max, d.rows.length);
    });
  $('d-openx').onchange = () => edit((l) => void (l.door && (l.door.openX = byte(num('d-openx')))));
  $('d-time').onchange = () => edit((l) => void (l.door && (l.door.time = Math.max(1, byte(num('d-time'))))));
  $('d-trace').onclick = () => edit((l) => traceDoor(l, num('d-depth') || 16, store.decoded));
  $('d-fill').onclick = () => edit((l) => fillDoor(l, store.decoded));
  $<HTMLTextAreaElement>('d-xs').onchange = (e) =>
    edit((l) => {
      const d = l.door;
      if (!d) return false;
      const xs = (e.target as HTMLTextAreaElement).value
        .split(/[\s,]+/)
        .filter(Boolean)
        .map((t) => (t.startsWith('$') ? parseInt(t.slice(1), 16) : Number(t)));
      if (!xs.length || xs.length > MAX_DOOR_ROWS || xs.some((v) => !Number.isFinite(v))) return false;
      d.rows = xs.map(byte);
      if (d.mode === 'reveal') d.max = Math.min(d.max, d.rows.length);
    });
  const preview = $<HTMLInputElement>('d-preview');
  preview.oninput = () => {
    store.doorPreview = Number(preview.value);
    store.changed(false);
  };

  // ---- rules
  $<HTMLSelectElement>('r-rev').onchange = (e) => edit((l) => void (l.rules.reverse = (e.target as HTMLSelectElement).value as Rule));
  $<HTMLSelectElement>('r-inv').onchange = (e) => edit((l) => void (l.rules.invisible = (e.target as HTMLSelectElement).value as Rule));
  const cycle = (fn: (c: { reverse: boolean; invisible: boolean }[]) => boolean | void) =>
    edit(() => {
      const p = store.project;
      return p ? fn(p.roundCycle) : false;
    });
  $('r-add').onclick = () =>
    cycle((c) => {
      if (c.length >= MAX_ROUNDS) return false;
      c.push({ reverse: false, invisible: false });
    });
  $('r-reset').onclick = () =>
    cycle(() => {
      store.project!.roundCycle = defaultRoundCycle();
    });
  $('r-rounds').onclick = (e) => {
    const t = e.target as HTMLElement;
    const li = t.closest<HTMLElement>('li[data-i]');
    if (!li) return;
    const i = Number(li.dataset.i);
    if (t.matches('button.r-del'))
      cycle((c) => {
        if (c.length <= 1) return false;
        c.splice(i, 1);
      });
    else if (t.matches('input[data-flag]'))
      cycle((c) => {
        const f = (t as HTMLInputElement).dataset.flag as 'reverse' | 'invisible';
        c[i] = { ...c[i], [f]: (t as HTMLInputElement).checked };
      });
  };

  const setVal = (id: string, v: number | string) => {
    const el = $<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>(id);
    if (document.activeElement !== el) el.value = String(v);
  };

  return (l: Level) => {
    const d = l.door;
    const switches = l.objects.filter((o) => o.type === ObjType.SwitchLeft || o.type === ObjType.SwitchRight).length;
    $('d-none').hidden = !!d;
    $('d-edit').hidden = !d;
    $('d-sum').textContent = d
      ? `${d.side} wall, row ${hex3(d.top)}, ${d.rows.length} rows${switches ? '' : ' — no switch!'}`
      : switches
        ? `none (${switches} switch${switches > 1 ? 'es' : ''} with nothing to open)`
        : 'none';
    if (d) {
      setVal('d-side', d.side);
      setVal('d-mode', d.mode);
      setVal('d-top', d.top);
      setVal('d-rows', d.rows.length);
      setVal('d-max', d.max);
      setVal('d-openx', d.openX);
      setVal('d-time', d.time);
      setVal('d-xs', d.rows.map(hex2).join(','));
      $('d-max-label').textContent = d.mode === 'reveal' ? 'rows that open' : 'max opening';
      $('d-openx-box').hidden = d.mode !== 'reveal';
      preview.max = String(d.max);
      if (store.doorPreview > d.max) store.doorPreview = d.max;
      preview.value = String(store.doorPreview);
      $('d-preview-v').textContent = store.doorPreview ? `open ${store.doorPreview} of ${d.max}` : 'closed';
      const t = doorTimeline(d);
      const full = t.filter((b) => b === d.max).length;
      $('d-info').textContent =
        d.mode === 'slide'
          ? `Opens by moving the edge ${d.max} X units ${d.side === 'left' ? 'left' : 'right'}, one per tick. ` +
            `Fully open for ${full} ticks, closed again after ${t.length} ticks.`
          : `The top ${d.max} rows open (to X ${hex2(d.openX)}), one per tick. Fully open for ${full} ticks, closed again after ${t.length} ticks.`;
    }

    setVal('r-rev', l.rules.reverse);
    setVal('r-inv', l.rules.invisible);
    const c = store.project!.roundCycle;
    const custom = l.rules.reverse !== 'round' || l.rules.invisible !== 'round';
    $('r-sum').textContent = custom ? '(this level has its own rules)' : '';
    $('r-level-info').textContent =
      'This level in each round: ' +
      c.map((r, i) => `${i + 1}: ${flagText(applyRule(l.rules.reverse, r.reverse), applyRule(l.rules.invisible, r.invisible))}`).join(', ') +
      ', then repeating.';
    $('r-rounds').innerHTML = c
      .map(
        (r, i) => `<li data-i="${i}">round ${i + 1}
          <label class="inline"><input type="checkbox" data-flag="reverse"${r.reverse ? ' checked' : ''}> reverse</label>
          <label class="inline"><input type="checkbox" data-flag="invisible"${r.invisible ? ' checked' : ''}> invisible</label>
          ${c.length > 1 ? '<button class="r-del" title="remove this round">✕</button>' : ''}</li>`,
      )
      .join('');
    $<HTMLButtonElement>('r-add').disabled = c.length >= MAX_ROUNDS;
  };
}
