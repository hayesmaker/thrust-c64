import './style.css';
import { attachInput } from './editor/input';
import { loadModSource, mountPanel, openAsmFiles, toast } from './editor/panel';
import { PlayerOverlay } from './editor/player';
import { Store } from './editor/store';
import { View } from './editor/view';

const store = new Store();
const view = new View(document.getElementById('view') as HTMLCanvasElement, store);
const player = new PlayerOverlay(document.getElementById('stage')!);
const updatePanel = mountPanel(document.getElementById('panel')!, store, view, player);
attachInput(view, store);
// the game reads the keyboard: pause editor shortcuts while it is shown
player.onOpen = () => (store.inputPaused = true);
player.onClose = () => {
  store.inputPaused = false;
  view.canvas.focus();
};

const empty = document.getElementById('empty')!;
store.onChange(() => {
  empty.hidden = !!store.project;
  view.rebuildTerrain();
  view.requestDraw();
  updatePanel();
});

// drop .asm / .json files anywhere
window.addEventListener('dragover', (e) => e.preventDefault());
window.addEventListener('drop', async (e) => {
  e.preventDefault();
  const files = [...(e.dataTransfer?.files ?? [])];
  if (!files.length) return;
  try {
    if (files[0].name.endsWith('.json')) store.fromJSON(JSON.parse(await files[0].text()));
    else toast(await openAsmFiles(store, files));
    view.fitLevel();
  } catch (err) {
    toast(String(err));
  }
});
window.addEventListener('beforeunload', () => store.saveNow());

async function start() {
  if (store.restoreAutosave()) {
    toast('Restored autosaved project');
  } else {
    try {
      await loadModSource(store);
    } catch {
      store.changed(false); // show the empty state
    }
  }
  view.fitLevel();
}
start();

// dev builds: handle for debugging and browser tests
if (import.meta.env.DEV) Object.assign(window, { editor: { store, view, player } });
