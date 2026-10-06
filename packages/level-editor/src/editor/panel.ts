// Side panel: level settings, selection editor, objects, restart points,
// checks, live tables, export, project I/O.

import { PALETTE, hex2, hex3 } from '../c64';
import { formatValue } from '../model/asm';
import {
  COLOUR_KEYS,
  LEVEL_COUNT,
  type Level,
  OBJ_NAMES,
  type Project,
  type Wall,
  loadProject,
  saveProject,
  wallTables,
} from '../model/level';
import { ANGLE_NAMES, GUN_SPREAD, gunArc, gunBase, gunParam, gunSpread, isGun, snapObject } from '../model/objects';
import { pointsToRuns, segmentSteps } from '../model/terrain';
import { AUTHOR_MAX, TITLE_MAX, authorText, fontText, fontTyping, nameProblem, titleText } from '../model/title';
import { type MemState, levelBytes, memoryAreas, memoryIssues, validateLevel, worstState } from '../model/validate';
import { type BuildError, type BuildResult, type Source, build, buildFileUrl, fetchBuildFile, getSource, getTemplate } from './api';
import { download, terrainAsm } from './export';
import { confirmDiscard, forgetFile, openGameFile, pickGameFile, saveGame } from './files';
import { swatchColour } from './look';
import { DOOR_HTML, RULES_HTML, mountDoorRules } from './door-panel';
import { deleteSelection } from './input';
import { addObject, addRestart, centreWindow, movePoint, reorderObject, sortObjects } from './ops';
import { type PlayerOverlay } from './player';
import { DEFAULT_NAME, type Side, type Store } from './store';
import { WALL_COLOUR, type View } from './view';

const COLOUR_LABELS: Record<string, string> = {
  terrain: 'terrain + text',
  mc1: 'bitmap "01"',
  mc3: 'bitmap "11" + pod',
  status: 'status labels',
  objects: 'guns, stand, generator',
  shield: 'shield + fuel label',
};

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => `&#${c.charCodeAt(0)};`);

const C64READY_KEY = 'thrust-level-editor:c64ready-url';
const C64READY_DEFAULT = 'https://hayesmaker.github.io/c64-ready/';
const FULLSCREEN_KEY = 'thrust-level-editor:play-fullscreen';

export function mountPanel(root: HTMLElement, store: Store, view: View, player: PlayerOverlay): () => void {
  root.innerHTML = `
    <header>
      <div class="title">
        <h1>Thrust level editor <span class="version" title="editor version">${__APP_VERSION__}</span></h1>
        <a class="donate" href="https://ko-fi.com/c64cade" target="_blank" rel="noopener" title="Support the author on Ko-fi">♥ Donate</a>
      </div>
      <div class="row">
        <button id="p-undo" title="Ctrl+Z">Undo</button>
        <button id="p-redo" title="Ctrl+Shift+Z">Redo</button>
        <button id="p-fit" title="F">Fit</button>
        <button id="p-guide" title="? : open the user guide">Guide</button>
      </div>
    </header>
    <section>
      <h2>Game</h2>
      <label>name <input type="text" id="p-game-name" spellcheck="false" maxlength="${TITLE_MAX}" placeholder="needed to build: shown on the title screen"></label>
      <label>author <input type="text" id="p-game-author" spellcheck="false" maxlength="${AUTHOR_MAX}" placeholder="shown as BY …"></label>
      <div class="small muted" id="p-game-title"></div>
      <div class="small" id="p-game-file"></div>
      <div class="row">
        <button id="p-save" class="primary" title="Ctrl+S">Save</button>
        <button id="p-save-as" title="Ctrl+Shift+S">Save as…</button>
      </div>
      <div class="row">
        <button id="p-open-json" title="Ctrl+O: open a game (.json)">Open…</button>
        <button id="p-new" title="a new game from the template: the original six levels">New from template</button>
      </div>
      <input type="file" id="p-file-json" accept=".json,application/json" hidden>
    </section>
    <section>
      <h2>Level</h2>
      <div class="levels" id="p-levels"></div>
      <div class="muted" id="p-level-info"></div>
      <div id="p-memory"></div>
      <div class="row"><button id="p-revert" title="put this level back the way the template has it">Reset level to template</button></div>
    </section>
    <section>
      <h2>Build and play</h2>
      <div id="p-mem-banner" hidden></div>
      <label><input type="checkbox" id="p-start-here" checked> start the game on this level</label>
      <label><input type="checkbox" id="p-fullscreen"> play full screen</label>
      <div class="row">
        <button id="p-play" class="primary" title="Ctrl+Enter">Build &amp; play</button>
        <button id="p-build">Build</button>
      </div>
      <div id="p-build-status" class="small muted"></div>
      <div class="row">
        <button id="p-dl-prg" disabled>Download PRG</button>
        <button id="p-c64ready" disabled title="open the build in c64-ready (URL under View)">Open in c64-ready</button>
      </div>
    </section>
    <section>
      <h2 id="p-sel-title">Selection</h2>
      <div id="p-sel"></div>
    </section>
    <details open>
      <summary>Checks <span id="p-check-count"></span></summary>
      <ul class="issues" id="p-checks"></ul>
    </details>
    <details open>
      <summary>Objects <span class="muted" id="p-obj-count"></span></summary>
      <div class="add-row" id="p-add-obj"></div>
      <ol class="list" id="p-objects" start="0"></ol>
      <div class="row">
        <button id="p-snap-all" title="put every object of this level back on the terrain">Snap all to terrain</button>
        <button id="p-sort" title="pod stand, generator, fuel, then the rest">Sort objects</button>
      </div>
    </details>
    <details open>
      <summary>Restart points</summary>
      <ol class="list" id="p-restarts" start="0"></ol>
      <div class="row"><button id="p-add-restart">Add restart point</button></div>
    </details>
    ${DOOR_HTML}
    <details>
      <summary>Gravity and colours</summary>
      <label class="inline">gravity <input type="number" id="p-gravity" min="0" max="255"> <span class="muted" id="p-gravity-hex"></span></label>
      <div class="muted small">Original levels: 5, 7, 9, 11, 12, 13 (bigger = stronger).</div>
      <div id="p-colours"></div>
    </details>
    ${RULES_HTML}
    <details>
      <summary>Terrain tables</summary>
      <div id="p-tables"></div>
    </details>
    <details>
      <summary>Assembler files</summary>
      <div class="col">
        <button id="p-copy">Copy terrain .byte lines</button>
        <div class="row">
          <button id="p-dl-levels">levels.asm</button>
          <button id="p-dl-tables">level_tables.asm</button>
        </div>
        <div class="muted small">The game as the mod's two level files (objects, restart points, gravity and colours included), for building by hand.</div>
        <div class="row"><button id="p-open-asm" title="start a new game from levels.asm and/or level_tables.asm">Import .asm files</button></div>
      </div>
      <input type="file" id="p-file-asm" accept=".asm,.s,.txt" multiple hidden>
    </details>
    <section>
      <h2>View</h2>
      <label><input type="checkbox" id="p-show-objects" checked> objects and restart points</label>
      <label><input type="checkbox" id="p-show-screen" checked> screen windows</label>
      <label><input type="checkbox" id="p-show-arcs"> firing arcs of all guns</label>
      <label><input type="checkbox" id="p-game-colours"> objects in the level's game colours (off: one colour per type)</label>
      <label><input type="checkbox" id="p-snap" checked> objects snap to the terrain (Alt while dragging inverts)</label>
      <label>c64-ready URL <input type="text" id="p-c64ready-url" spellcheck="false"></label>
    </section>
    <details class="help">
      <summary>Controls</summary>
      <dl>
        <dt>drag point</dt><dd>move (Shift: whole step per row)</dd>
        <dt>click a wall line</dt><dd>add a point</dd>
        <dt>drag object</dt><dd>move, snaps to terrain (Alt: free)</dd>
        <dt>drag restart cross</dt><dd>move ship start + window</dd>
        <dt>drag door tab / row dot</dt><dd>move door / one row (Shift: all rows)</dd>
        <dt>right-click / Del</dt><dd>delete</dd>
        <dt>arrows</dt><dd>nudge (Shift: ×8)</dd>
        <dt>drag / wheel</dt><dd>pan</dd>
        <dt>Ctrl+wheel, +/-</dt><dd>zoom</dd>
        <dt>F, 1-6</dt><dd>fit, pick level</dd>
        <dt>?</dt><dd>user guide</dd>
      </dl>
    </details>
    <div id="toast"></div>
  `;
  const $ = <T extends HTMLElement = HTMLElement>(id: string) => root.querySelector<T>('#' + id)!;
  /** Apply an edit to the current level as one undo step. `terrain`: the
   *  edit changed a wall, so resting objects follow it. */
  const edit = (fn: (l: Level) => boolean | void, terrain = false) => {
    if (!store.current) return;
    store.checkpoint();
    if (fn(store.current) === false) store.cancelCheckpointIfUnchanged();
    else if (terrain) store.terrainChanged();
    else store.changed();
  };

  const updateDoorRules = mountDoorRules(root, store, view, edit);

  // ---- header + level
  const levelBox = $('p-levels');
  for (let n = 0; n < LEVEL_COUNT; n++) {
    const b = document.createElement('button');
    b.textContent = String(n);
    b.title = `level ${n} (mission ${n + 1}) — key ${n + 1}`;
    b.onclick = () => {
      store.setLevel(n);
      view.fitLevel();
    };
    levelBox.append(b);
  }
  $('p-undo').onclick = () => store.undo();
  $('p-redo').onclick = () => store.redo();
  $('p-fit').onclick = () => view.fitLevel();

  // ---- objects
  const viewCentre = () => view.toWorld(view.canvas.clientWidth / 2, view.canvas.clientHeight / 2);
  const addBox = $('p-add-obj');
  OBJ_NAMES.forEach((name, type) => {
    const b = document.createElement('button');
    b.className = 'add-obj';
    b.title = `add ${name} at the centre of the view`;
    b.innerHTML = `<span class="swatch" data-type="${type}"></span>${esc(name)}`;
    b.onclick = () =>
      edit((l) => {
        const c = viewCentre();
        const i = addObject(l, type, c.x, c.row, store.decoded);
        store.selection = { kind: 'object', index: i };
      });
    addBox.append(b);
  });
  $('p-snap-all').onclick = () =>
    edit((l) => {
      let n = 0;
      l.objects = l.objects.map((o) => {
        const s = snapObject(o, store.decoded.left, store.decoded.right);
        if (!s || (s.x === o.x && s.y === o.y)) return o;
        n++;
        return { ...o, ...s };
      });
      toast(n ? `Snapped ${n} object${n > 1 ? 's' : ''} to the terrain` : 'All objects already rest on the terrain');
      return n > 0;
    });
  $('p-sort').onclick = () =>
    edit((l) => {
      store.selection = null;
      sortObjects(l);
    });
  $('p-objects').onclick = (e) => {
    const li = (e.target as HTMLElement).closest<HTMLElement>('li[data-i]');
    if (!li) return;
    store.selection = { kind: 'object', index: Number(li.dataset.i) };
    store.changed(false);
  };

  // ---- restart points
  $('p-add-restart').onclick = () =>
    edit((l) => {
      const c = viewCentre();
      store.selection = { kind: 'restart', index: addRestart(l, c.x, c.row) };
    });
  $('p-restarts').onclick = (e) => {
    const li = (e.target as HTMLElement).closest<HTMLElement>('li[data-i]');
    if (!li) return;
    store.selection = { kind: 'restart', index: Number(li.dataset.i) };
    store.changed(false);
  };

  // ---- checks
  $('p-checks').onclick = (e) => {
    const li = (e.target as HTMLElement).closest<HTMLElement>('li[data-kind]');
    if (!li) return;
    const kind = li.dataset.kind;
    const i = Number(li.dataset.i);
    if (kind === 'object' || kind === 'restart' || kind === 'door') {
      store.selection = { kind, index: i };
      store.changed(false);
    }
  };

  // ---- gravity + colours
  const gravityIn = $<HTMLInputElement>('p-gravity');
  gravityIn.onchange = () => edit((l) => void (l.gravity = Math.max(0, Math.min(255, Number(gravityIn.value) | 0))));
  const colourBox = $('p-colours');
  colourBox.innerHTML = COLOUR_KEYS.map(
    (k) => `
      <div class="colour-row"><span class="colour-label">${COLOUR_LABELS[k]}</span>
        <span class="palette">${PALETTE.map((c, n) => `<button data-key="${k}" data-c="${n}" style="background:${c}" title="${n}"></button>`).join('')}</span>
      </div>`,
  ).join('');
  colourBox.onclick = (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('button[data-key]');
    if (!b) return;
    edit((l) => void (l.colours[b.dataset.key as (typeof COLOUR_KEYS)[number]] = Number(b.dataset.c)));
  };

  // ---- export
  $('p-copy').onclick = async () => {
    const l = store.current;
    if (!l) return;
    const text = terrainAsm(l);
    try {
      await navigator.clipboard.writeText(text);
      toast(`Copied level ${l.index} terrain tables`);
    } catch {
      download(`level_${l.index}_terrain.asm`, text);
      toast('Clipboard blocked: downloaded instead');
    }
  };
  const saved = () => saveProject(store.project!, { title: store.name, author: store.author });
  $('p-dl-levels').onclick = () => store.project && download('levels.asm', saved().levelsAsm);
  $('p-dl-tables').onclick = () => store.project && download('level_tables.asm', saved().tablesAsm);

  // ---- game files
  const nameInput = $<HTMLInputElement>('p-game-name');
  const authorInput = $<HTMLInputElement>('p-game-author');
  const showTitle = (name: string, author: string) => {
    const a = authorText(author);
    $('p-game-title').textContent = nameProblem(name)
      ? 'title screen: the game needs a name'
      : `title screen: ${titleText(name)}${a ? ` / ${a}` : ''}`;
  };
  /** Keep a box to what the title screen font can show (upper case), and
   *  return its text. Keeps the caret where it was. */
  const fontBox = (input: HTMLInputElement, max: number): string => {
    const v = input.value;
    const caret = input.selectionStart ?? v.length;
    const next = fontTyping(v, max);
    if (next !== v) {
      const at = fontTyping(v.slice(0, caret), max).length;
      input.value = next;
      input.setSelectionRange(at, at);
    }
    return next.trim();
  };
  // stored on every keystroke, so a shortcut (Ctrl+Enter, Ctrl+S) typed in
  // the box uses what is there
  nameInput.oninput = () => {
    const name = fontBox(nameInput, TITLE_MAX);
    if (name !== store.name) store.setName(name);
    if (name) nameInput.classList.remove('needed');
    showTitle(name, store.author);
  };
  authorInput.oninput = () => {
    const author = fontBox(authorInput, AUTHOR_MAX);
    if (author !== store.author) store.setAuthor(author);
    showTitle(store.name, author);
  };
  nameInput.onchange = () => (nameInput.value = fontText(store.name, TITLE_MAX));
  authorInput.onchange = () => (authorInput.value = fontText(store.author, AUTHOR_MAX));
  const save = async (as: boolean) => {
    try {
      const f = await saveGame(store, as);
      if (f) toast(`Saved ${f}`);
    } catch (e) {
      toast(`Save failed: ${e instanceof Error ? e.message : e}`);
    }
  };
  $('p-save').onclick = () => save(false);
  $('p-save-as').onclick = () => save(true);
  const fileJson = $<HTMLInputElement>('p-file-json');
  const opened = (name: string) => {
    view.fitLevel();
    toast(`Opened ${name}`);
  };
  const open = async () => {
    if (!confirmDiscard(store, 'Open another game?')) return;
    try {
      if (!(await pickGameFile(store))) return fileJson.click();
      if (store.fileName) opened(store.fileName);
    } catch (e) {
      toast(`Could not open the game: ${e instanceof Error ? e.message : e}`);
    }
  };
  $('p-open-json').onclick = open;
  fileJson.onchange = async () => {
    const f = fileJson.files?.[0];
    fileJson.value = '';
    if (!f) return;
    try {
      await openGameFile(store, f);
      opened(f.name);
    } catch (e) {
      toast(`Could not open ${f.name}: ${e instanceof Error ? e.message : e}`);
    }
  };
  $('p-new').onclick = async () => {
    if (!confirmDiscard(store, 'Start a new game from the template?')) return;
    try {
      await loadModSource(store);
      view.fitLevel();
      toast('New game from the template');
    } catch (e) {
      toast(`Could not load the template (${e instanceof Error ? e.message : e}). Is the editor server running?`);
    }
  };
  window.addEventListener('keydown', (e) => {
    if (!(e.ctrlKey || e.metaKey) || store.inputPaused || !store.project) return;
    const k = e.key.toLowerCase();
    if (k === 's') {
      e.preventDefault();
      save(e.shiftKey);
    } else if (k === 'o') {
      e.preventDefault();
      open();
    }
  });
  const fileAsm = $<HTMLInputElement>('p-file-asm');
  $('p-open-asm').onclick = () => {
    if (confirmDiscard(store, 'Start a new game from .asm files?')) fileAsm.click();
  };
  fileAsm.onchange = async () => {
    if (fileAsm.files?.length) await openAsmFiles(store, [...fileAsm.files]).then(toast, (e) => toast(String(e)));
    fileAsm.value = '';
    view.fitLevel();
  };
  $('p-revert').onclick = () => {
    const p = store.project;
    if (!p || !confirm(`Reset level ${store.level} to the template's version? (Undo brings your version back.)`)) return;
    store.checkpoint();
    p.levels[store.level] = original(p).levels[store.level];
    store.selection = null;
    store.changed();
  };

  // ---- build and play
  let lastBuild: BuildResult | null = null;
  let building = false;
  const buildStatus = $('p-build-status');
  const c64readyUrl = $<HTMLInputElement>('p-c64ready-url');
  c64readyUrl.value = readPref(C64READY_KEY) ?? C64READY_DEFAULT;
  c64readyUrl.onchange = () => writePref(C64READY_KEY, c64readyUrl.value.trim() || C64READY_DEFAULT);

  async function runBuild(play: boolean) {
    const p = store.project;
    if (!p || building) return;
    const problem = nameProblem(store.name);
    if (problem) {
      buildStatus.className = 'small warn';
      buildStatus.textContent = problem;
      if (player.isOpen) player.setStatus('the game needs a name: see the panel');
      nameInput.classList.add('needed');
      nameInput.focus();
      return;
    }
    building = true;
    // full screen needs the click itself, so the player opens before the build
    if (play) player.open(fullscreen.checked);
    const levelNo = store.level;
    const startHere = $<HTMLInputElement>('p-start-here').checked;
    const out = saveProject(p, { title: store.name, author: store.author });
    buildStatus.className = 'small muted';
    buildStatus.textContent = 'building…';
    if (player.isOpen) player.setStatus('building…');
    try {
      const r = await build(out.levelsAsm, out.tablesAsm, startHere ? levelNo : null);
      lastBuild = r;
      $<HTMLButtonElement>('p-dl-prg').disabled = !r.ok;
      $<HTMLButtonElement>('p-c64ready').disabled = !r.ok;
      if (!r.ok) {
        buildStatus.className = 'small';
        buildStatus.innerHTML = renderBuildErrors(r, out);
        player.buildFailed();
        return;
      }
      const start = r.startLevel !== null ? `, starts on level ${r.startLevel}` : '';
      buildStatus.className = 'small ok';
      buildStatus.textContent = `built in ${(r.ms / 1000).toFixed(1)} s, ${r.prgBytes} bytes${start}`;
      if (play) await player.play(await fetchBuildFile(r.id, 'play.prg'), `level ${levelNo}${start ? '' : ' (game from level 0)'}`);
    } catch (e) {
      buildStatus.className = 'small warn';
      buildStatus.textContent = String(e instanceof Error ? e.message : e);
      player.buildFailed();
    } finally {
      building = false;
    }
  }
  // full screen by default on phones and tablets; the choice is remembered
  const fullscreen = $<HTMLInputElement>('p-fullscreen');
  const fsPref = readPref(FULLSCREEN_KEY);
  fullscreen.checked = fsPref ? fsPref === 'on' : matchMedia('(pointer: coarse)').matches;
  fullscreen.onchange = () => writePref(FULLSCREEN_KEY, fullscreen.checked ? 'on' : 'off');
  $('p-play').onclick = () => runBuild(true);
  player.onRebuild = () => runBuild(true);
  $('p-build').onclick = () => runBuild(false);
  window.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter' && !player.isOpen) {
      e.preventDefault();
      runBuild(true);
    }
  });
  $('p-dl-prg').onclick = () => {
    if (!lastBuild?.ok) return;
    const a = document.createElement('a');
    a.href = buildFileUrl(lastBuild.id, 'play.prg');
    a.download = `thrusty-levels-${lastBuild.id}.prg`;
    a.click();
  };
  $('p-c64ready').onclick = () => {
    if (!lastBuild?.ok) return;
    const prgUrl = new URL(buildFileUrl(lastBuild.id, 'play.prg'), location.href).href;
    const base = readPref(C64READY_KEY) ?? C64READY_DEFAULT;
    window.open(`${base}${base.includes('?') ? '&' : '?'}game=${encodeURIComponent(prgUrl)}`, '_blank');
  };

  // ---- view toggles
  const toggle = (id: string, fn: (on: boolean) => void) => {
    $<HTMLInputElement>(id).onchange = (e) => {
      fn((e.target as HTMLInputElement).checked);
      view.requestDraw();
    };
  };
  toggle('p-show-objects', (on) => (view.showObjects = on));
  toggle('p-show-screen', (on) => (view.showScreen = on));
  toggle('p-show-arcs', (on) => (view.showArcs = on));
  toggle('p-game-colours', (on) => {
    view.gameColours = on;
    store.changed(false); // recolour the swatches
  });
  toggle('p-snap', (on) => (store.snapObjects = on));

  // ---- selection editor (inputs are rebuilt only when the selection changes)
  const selBox = $('p-sel');
  let selKey = '';
  const num = (id: string) => $<HTMLInputElement>(id);
  /** Set an input's value unless the user is typing in it. */
  const setVal = (id: string, v: number | string) => {
    const el = root.querySelector<HTMLInputElement | HTMLSelectElement>('#' + id);
    if (el && document.activeElement !== el) el.value = String(v);
  };

  function renderSelection(l: Level | null) {
    const sel = store.selection;
    const valid =
      sel &&
      l &&
      (sel.kind === 'point'
        ? !!l[sel.side].points[sel.index]
        : sel.kind === 'object'
          ? !!l.objects[sel.index]
          : sel.kind === 'door'
            ? !!l.door && sel.index < l.door.rows.length
            : !!l.restarts[sel.index]);
    if (!sel || !l || !valid) {
      selKey = '';
      $('p-sel-title').textContent = 'Selection';
      selBox.innerHTML =
        '<div class="muted">Click a wall point, object or restart cross. Click a wall line to add a point; add objects below.</div>';
      return;
    }
    const key = `${store.level}:${sel.kind}:${sel.kind === 'point' ? sel.side : ''}:${sel.index}`;
    if (sel.kind === 'point') {
      const w = l[sel.side];
      const p = w.points[sel.index];
      if (key !== selKey) {
        selKey = key;
        $('p-sel-title').textContent = 'Wall point';
        selBox.innerHTML = `
          <div class="kv"><span class="swatch" style="background:${WALL_COLOUR[sel.side]}"></span>${sel.side} wall, point ${sel.index}</div>
          <div class="grid2">
            <label>row <input type="number" id="s-row" min="255"></label>
            <label>X <input type="number" id="s-x" min="0" max="255"></label>
          </div>
          <div class="muted" id="s-info"></div>
          <div class="row"><button id="s-del">Delete point</button></div>`;
        const apply = () =>
          edit((l2) => {
            const w2 = l2[sel.side];
            const cur = w2.points[sel.index];
            const xv = Number(num('s-x').value) & 0xff;
            const dx = ((xv - (cur.x & 0xff) + 384) % 256) - 128; // nearest copy: keep X unwrapped
            return movePoint(w2, sel.index, Number(num('s-row').value), cur.x + dx);
          }, true);
        num('s-row').onchange = apply;
        num('s-x').onchange = apply;
        $('s-del').onclick = () => deleteSelection(store);
      }
      setVal('s-row', p.row);
      setVal('s-x', p.x & 0xff);
      const prev = w.points[sel.index - 1];
      $('s-info').innerHTML = `row ${hex3(p.row)}, X ${hex2(p.x)}<br>` + describeSegment(prev.row, prev.x, p.row, p.x);
      return;
    }

    if (sel.kind === 'door') {
      const d = l.door!;
      if (key !== selKey) {
        selKey = key;
        $('p-sel-title').textContent = sel.index < 0 ? 'Door' : `Door row ${sel.index}`;
        selBox.innerHTML =
          sel.index < 0
            ? `<div class="muted">Drag the tab to move the door (Shift: sideways only); arrows nudge it. Edit it under Door below.</div>
               <div class="row"><button id="s-ddel">Delete door</button></div>`
            : `<label>closed X <input type="number" id="s-dx" min="0" max="255"></label>
               <div class="muted" id="s-dinfo"></div>
               <div class="row"><button id="s-ddel">Delete row</button></div>`;
        $('s-ddel').onclick = () => deleteSelection(store);
        if (sel.index >= 0)
          num('s-dx').onchange = () =>
            edit((l2) => {
              if (!l2.door) return false;
              const x = Math.max(0, Math.min(255, Number(num('s-dx').value) | 0));
              if (l2.door.rows[sel.index] === x) return false;
              l2.door.rows[sel.index] = x;
            });
      }
      if (sel.index >= 0) {
        setVal('s-dx', d.rows[sel.index]);
        $('s-dinfo').textContent = `row ${hex3(d.top + sel.index)}, closed X ${hex2(d.rows[sel.index])}`;
      }
      return;
    }

    if (sel.kind === 'object') {
      const o = l.objects[sel.index];
      if (key !== selKey) {
        selKey = key;
        $('p-sel-title').textContent = `Object ${sel.index}`;
        selBox.innerHTML = `
          <label>type <select id="s-type">${OBJ_NAMES.map((n, t) => `<option value="${t}">${t}: ${esc(n)}</option>`).join('')}</select></label>
          <div class="grid2">
            <label>X <input type="number" id="s-ox" min="0" max="255"></label>
            <label>Y <input type="number" id="s-oy" min="0" max="65535"></label>
          </div>
          <div id="s-gun"></div>
          <div class="muted" id="s-oinfo"></div>
          <div class="row">
            <button id="s-up" title="earlier in the object list">▲</button>
            <button id="s-down" title="later in the object list">▼</button>
            <button id="s-snap">Snap to terrain</button>
            <button id="s-odel">Delete</button>
          </div>`;
        const i = sel.index;
        $<HTMLSelectElement>('s-type').onchange = (e) =>
          edit((l2) => {
            const t = Number((e.target as HTMLSelectElement).value);
            l2.objects[i] = { ...l2.objects[i], type: t };
          });
        const applyPos = () =>
          edit((l2) => {
            const cur = l2.objects[i];
            const x = Number(num('s-ox').value) & 0xff;
            const y = Math.max(0, Math.min(0xffff, Number(num('s-oy').value) | 0));
            if (x === cur.x && y === cur.y) return false;
            l2.objects[i] = { ...cur, x, y };
          });
        num('s-ox').onchange = applyPos;
        num('s-oy').onchange = applyPos;
        $('s-up').onclick = () => edit((l2) => void (store.selection = { kind: 'object', index: reorderObject(l2, i, -1) }));
        $('s-down').onclick = () => edit((l2) => void (store.selection = { kind: 'object', index: reorderObject(l2, i, 1) }));
        $('s-snap').onclick = () =>
          edit((l2) => {
            const s = snapObject(l2.objects[i], store.decoded.left, store.decoded.right);
            if (!s) {
              toast('No terrain to rest on near this object');
              return false;
            }
            l2.objects[i] = { ...l2.objects[i], ...s };
          });
        $('s-odel').onclick = () => deleteSelection(store);
      }
      setVal('s-type', o.type);
      setVal('s-ox', o.x);
      setVal('s-oy', o.y);
      renderGun(sel.index, o.type, o.gun);
      const s = snapObject(o, store.decoded.left, store.decoded.right);
      $('s-oinfo').innerHTML =
        `X ${hex2(o.x)}, Y ${hex3(o.y)}` +
        (s && (s.x !== o.x || s.y !== o.y) ? ' — <span class="edited">not resting on the terrain</span>' : '');
      return;
    }

    // restart point
    const r = l.restarts[sel.index];
    if (key !== selKey) {
      selKey = key;
      const i = sel.index;
      $('p-sel-title').textContent = i === 0 ? 'Start position' : `Restart point ${i}`;
      selBox.innerHTML = `
        <div class="grid2">
          <label>ship X <input type="number" id="s-sx" min="0" max="255"></label>
          <label>ship Y <input type="number" id="s-sy" min="0" max="65535"></label>
          <label>window X <input type="number" id="s-wx" min="0" max="255"></label>
          <label>window Y <input type="number" id="s-wy" min="0" max="65535"></label>
        </div>
        <div class="muted small">The window is the top-left of the scrolled view; the
          dashed box is the approximate screen. Usual offset: ship − ($16, $64).</div>
        <div class="row">
          <button id="s-centre">Centre window on ship</button>
          <button id="s-rdel" ${i === 0 ? 'disabled title="the start position cannot be deleted"' : ''}>Delete</button>
        </div>`;
      const apply = () =>
        edit((l2) => {
          const cur = l2.restarts[i];
          const next = {
            shipX: Number(num('s-sx').value) & 0xff,
            shipY: Math.max(0, Number(num('s-sy').value) | 0),
            windowX: Number(num('s-wx').value) & 0xff,
            windowY: Math.max(0, Number(num('s-wy').value) | 0),
          };
          if (JSON.stringify(cur) === JSON.stringify(next)) return false;
          l2.restarts[i] = next;
        });
      for (const id of ['s-sx', 's-sy', 's-wx', 's-wy']) num(id).onchange = apply;
      $('s-centre').onclick = () => edit((l2) => void (l2.restarts[i] = centreWindow(l2.restarts[i])));
      $('s-rdel').onclick = () => deleteSelection(store);
    }
    setVal('s-sx', r.shipX);
    setVal('s-sy', r.shipY);
    setVal('s-wx', r.windowX);
    setVal('s-wy', r.windowY);
  }

  /** Gun direction + spread editor (rebuilt when the type changes). */
  let gunKey = '';
  function renderGun(i: number, type: number, param: number) {
    const box = $('s-gun');
    const key = `${selKey}:${isGun(type)}`;
    if (!isGun(type)) {
      if (gunKey !== key) box.innerHTML = '';
      gunKey = key;
      return;
    }
    if (gunKey !== key) {
      gunKey = key;
      box.innerHTML = `
        <div class="grid2">
          <label>fires from <select id="s-gbase">${ANGLE_NAMES.map((n, k) => `<option value="${k * 4}">${n} (${k * 4})</option>`).join('')}</select></label>
          <label>spread <select id="s-gspread">${GUN_SPREAD.map((m, k) => `<option value="${k}">${m + 3} steps (${((m + 3) * 11.25).toFixed(0)}°)</option>`).join('')}</select></label>
        </div>
        <div class="muted small" id="s-garc"></div>`;
      const apply = () =>
        edit((l2) => {
          const o = l2.objects[i];
          const g = gunParam(Number($<HTMLSelectElement>('s-gbase').value), Number($<HTMLSelectElement>('s-gspread').value), o.gun);
          if (g === o.gun) return false;
          l2.objects[i] = { ...o, gun: g };
        });
      $<HTMLSelectElement>('s-gbase').onchange = apply;
      $<HTMLSelectElement>('s-gspread').onchange = apply;
    }
    setVal('s-gbase', gunBase(param));
    setVal('s-gspread', gunSpread(param));
    const { from, to } = gunArc(param);
    const dir = (a: number) => ANGLE_NAMES[Math.round((a & 31) / 4) & 7];
    $('s-garc').textContent = `param ${hex2(param)}: fires ${dir(from)} → ${dir(to)} (directions ${from}–${to & 31} of 32, clockwise from up)`;
  }

  // ---- lists
  function renderLists(l: Level) {
    const sel = store.selection;
    $('p-obj-count').textContent = `(${l.objects.length})`;
    $('p-objects').innerHTML = l.objects
      .map(
        (o, i) =>
          `<li data-i="${i}" class="${sel?.kind === 'object' && sel.index === i ? 'sel' : ''}">
             <span class="swatch" data-type="${o.type}"></span>${esc(OBJ_NAMES[o.type] ?? `type ${o.type}`)}
             <span class="muted">${hex2(o.x)}, ${hex3(o.y)}</span></li>`,
      )
      .join('');
    $('p-restarts').innerHTML = l.restarts
      .map(
        (r, i) =>
          `<li data-i="${i}" class="${sel?.kind === 'restart' && sel.index === i ? 'sel' : ''}">
             ${i === 0 ? 'start' : `restart ${i}`} <span class="muted">ship ${hex2(r.shipX)}, ${hex3(r.shipY)}</span></li>`,
      )
      .join('');
    // object type swatches match the objects on the canvas
    for (const sw of root.querySelectorAll<HTMLElement>('.swatch[data-type]'))
      sw.style.background = swatchColour(Number(sw.dataset.type), l.colours, view.gameColours);
  }

  function renderChecks(l: Level) {
    const p = store.project!;
    const issues = [...memoryIssues(memoryAreas(p.levels, store.layout, p.roundCycle.length), l.index), ...validateLevel(l)];
    const bad = issues.filter((i) => i.severity !== 'info').length;
    $('p-check-count').innerHTML = bad ? `<span class="warn">(${bad})</span>` : '<span class="ok">✓</span>';
    $('p-checks').innerHTML =
      issues
        .map((i) => {
          const t = i.target;
          const data =
            t?.kind === 'door' ? 'data-kind="door" data-i="-1"' : t && t.kind !== 'wall' ? `data-kind="${t.kind}" data-i="${t.index}"` : '';
          return `<li class="${i.severity}" ${data}>${esc(i.message)}</li>`;
        })
        .join('') || '<li class="ok">No problems found.</li>';
  }

  let lastMemState: MemState = 'ok';
  function renderMemory(l: Level) {
    const areas = memoryAreas(store.project!.levels, store.layout, store.project!.roundCycle.length);
    const b = levelBytes(l);
    $('p-memory').innerHTML =
      areas
        .map((a) => {
          const pct = Math.min(100, (a.used / a.budget) * 100);
          const left = a.free >= 0 ? `${a.free} free` : `<b>${-a.free} over</b>`;
          return `<div class="meter ${a.state}"><div style="width:${pct}%"></div></div>
            <div class="small mem-${a.state}">${a.label}: ${a.used} of ~${a.budget} bytes · ${left}</div>`;
        })
        .join('') +
      `<div class="muted small">this level: terrain ${b.terrain}, objects ${b.objects}, restart points ${b.restarts} bytes</div>`;

    // banner next to Build & play, and a toast when it gets worse while editing
    const state = worstState(areas);
    const banner = $('p-mem-banner');
    const worst = areas.filter((a) => a.state === state).sort((x, y) => x.free - y.free)[0];
    banner.hidden = state === 'ok';
    banner.className = `mem-banner ${state}`;
    if (state === 'ok') banner.textContent = '';
    else if (worst)
      banner.textContent =
        state === 'over'
          ? `Out of memory: ${worst.label} is ${-worst.free} bytes over. The build will fail until you remove something.`
          : `Memory is tight: ${worst.free} bytes left for ${worst.label}.`;
    const rank = { ok: 0, tight: 1, over: 2 };
    if (rank[state] > rank[lastMemState]) toast(banner.textContent ?? '');
    lastMemState = state;
  }

  // ---- tables
  function renderTables(l: Level) {
    const orig = original(store.project!).levels[l.index];
    const wall = (side: Side, w: Wall, ow: Wall, a: string, b: string) => {
      const t = wallTables(w);
      const n = t.counts.length;
      const delta = 2 * (n - wallTables(ow).counts.length);
      const runs = w.raw ? null : pointsToRuns(w.points).length;
      return `
        <div class="table-head"><span class="swatch" style="background:${WALL_COLOUR[side]}"></span>
          ${side} wall (${a}/${b}) — ${n} entries, ${2 * n} bytes
          <span class="${w.raw ? 'muted' : 'edited'}">${w.raw ? 'original' : `edited, ${delta >= 0 ? '+' : ''}${delta} bytes`}</span>
          ${runs !== null ? `<span class="muted">${w.points.length - 1} points → ${runs} runs</span>` : ''}
        </div>
        <pre><b>${a}</b> ${t.counts.map(formatValue).join(',')}\n<b>${b}</b> ${t.steps.map(formatValue).join(',')}</pre>`;
    };
    $('p-tables').innerHTML = wall('left', l.left, orig.left, 'A', 'B') + wall('right', l.right, orig.right, 'C', 'D');
  }

  function update() {
    const p = store.project;
    const l = store.current;
    if (document.activeElement !== nameInput) nameInput.value = fontText(store.name, TITLE_MAX);
    if (document.activeElement !== authorInput) authorInput.value = fontText(store.author, AUTHOR_MAX);
    if (document.activeElement !== nameInput && document.activeElement !== authorInput) showTitle(store.name, store.author);
    const file = store.fileName ?? 'not saved yet';
    $('p-game-file').innerHTML = !p
      ? '<span class="muted">no game loaded</span>'
      : `<span class="muted">${esc(file)}</span>${store.dirty ? ' · <span class="warn">unsaved changes</span>' : ''}`;
    document.title = `${store.dirty ? '• ' : ''}${store.name || 'untitled'} – Thrust level editor`;
    $<HTMLButtonElement>('p-undo').disabled = !store.canUndo();
    $<HTMLButtonElement>('p-redo').disabled = !store.canRedo();
    [...levelBox.children].forEach((b, n) => b.classList.toggle('active', n === store.level));
    renderSelection(l);
    if (!l) return;
    $('p-level-info').textContent = `${l.objects.length} objects, ${l.restarts.length} restart points, gravity ${hex2(l.gravity)}`;
    setVal('p-gravity', l.gravity);
    $('p-gravity-hex').textContent = hex2(l.gravity);
    for (const b of colourBox.querySelectorAll<HTMLElement>('button[data-key]'))
      b.classList.toggle('active', l.colours[b.dataset.key as (typeof COLOUR_KEYS)[number]] === Number(b.dataset.c));
    updateDoorRules(l);
    renderMemory(l);
    renderChecks(l);
    renderLists(l);
    renderTables(l);
  }
  return update;
}

/** The project as originally loaded (cached per source text). */
let origCache: { key: string; project: Project } | null = null;
function original(p: Project): Project {
  const key = p.levelsAsm + '\0' + p.tablesAsm;
  if (origCache?.key !== key) origCache = { key, project: loadProject(p.levelsAsm, p.tablesAsm) };
  return structuredClone(origCache.project);
}

function describeSegment(r0: number, x0: number, r1: number, x1: number): string {
  const dy = r1 - r0;
  const dx = x1 - x0;
  let runs = 0;
  segmentSteps(dy, dx).forEach((v, i, a) => (runs += i === 0 || v !== a[i - 1] ? 1 : 0));
  const cost = runs > 1 ? ` <span class="edited">→ ${runs} table entries</span> (Shift-drag for a whole step)` : '';
  return describeShape(dy, dx) + cost;
}

function describeShape(dy: number, dx: number): string {
  const sx = (v: number) => (v >= 0 ? '+' : '') + v;
  if (dy === 1) return `ledge: 1 row, X ${sx(dx)}`;
  if (dx === 0) return `vertical: ${dy} rows`;
  if (dx % dy === 0) return `slope: ${dy} rows of ${sx(dx / dy)}`;
  if (Math.abs(dx) < dy) return `steep: ${dy} rows, X ${sx(dx)} (staircase, 1 step per ~${(dy / Math.abs(dx)).toFixed(1)} rows)`;
  return `${dy} rows, X ${sx(dx)} (mixed steps ${Math.trunc(dx / dy)} / ${Math.trunc(dx / dy) + Math.sign(dx)})`;
}

let toastTimer = 0;
export function toast(msg: string): void {
  const t = document.getElementById('toast');
  if (!t) return;
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => t.classList.remove('show'), 2600);
}

/** A new game: the template game (the original levels) if the server has
 *  one, else the mod's own levels. */
export async function loadModSource(store: Store): Promise<void> {
  const [s, t] = await Promise.all([getSource(), getTemplate()]);
  applyLayout(store, s);
  forgetFile();
  if (t) store.fromTemplate(t, DEFAULT_NAME);
  else store.load(loadProject(s.levelsAsm, s.tablesAsm), DEFAULT_NAME);
}

/** The layout belongs to the mod source on disk (thrust.asm), not to the
 *  project, so it always comes from the server. A server from before the
 *  layout existed sends none: keep what we have and say so. */
function applyLayout(store: Store, s: Source): void {
  if (!('layout' in s)) {
    toast('Restart the editor server (npm run dev) to pick up its changes');
    return;
  }
  store.layout = s.layout ?? null;
}

/** After restoring an autosave: take the layout from the server and warn if
 *  the mod source changed on disk since the project was loaded. */
export async function refreshFromServer(store: Store): Promise<void> {
  const s = await getSource();
  applyLayout(store, s);
  store.changed(false);
}

/** What differs from the loaded source, one line per level. */

/** KickAssembler errors with the table label each line belongs to. */
function renderBuildErrors(r: BuildResult, src: { levelsAsm: string; tablesAsm: string }): string {
  const files: Record<string, string> = { 'levels.asm': src.levelsAsm, 'level_tables.asm': src.tablesAsm };
  const where = (e: BuildError) => {
    const lines = files[e.file]?.split(/\r?\n/);
    if (!lines) return `${e.file}:${e.line}`;
    for (let i = e.line - 1; i >= 0; i--) {
      const m = /^([A-Za-z_]\w*):/.exec(lines[i]);
      if (m) return `${e.file}:${e.line} (${m[1]})`;
    }
    return `${e.file}:${e.line}`;
  };
  const list = r.errors.map((e) => `<li class="error">${esc(where(e))}: ${esc(e.message)}</li>`).join('');
  return `<div class="warn">Build failed</div><ul class="issues">${list || '<li class="error">see the log</li>'}</ul>
    <details><summary>KickAssembler log</summary><pre>${esc(r.log)}</pre></details>`;
}

function readPref(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writePref(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    // ignore: a preference only
  }
}

/** Open levels.asm and/or level_tables.asm (recognised by their labels). */
export async function openAsmFiles(store: Store, files: File[]): Promise<string> {
  let levels = store.project?.levelsAsm;
  let tables = store.project?.tablesAsm;
  const names: string[] = [];
  for (const f of files) {
    const text = await f.text();
    if (text.includes('terrain_data_level_0_A:')) levels = text;
    else if (text.includes('level_reset_data_sizes:')) tables = text;
    else throw new Error(`${f.name}: not levels.asm or level_tables.asm`);
    names.push(f.name);
  }
  if (!levels || !tables) throw new Error('Need both levels.asm and level_tables.asm');
  forgetFile();
  store.load(loadProject(levels, tables), 'imported game');
  return `Opened ${names.join(', ')}`;
}
