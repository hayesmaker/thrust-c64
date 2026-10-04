import './style.css';
import { confirmDiscard, openGameFile } from './editor/files';
import { GuideOverlay } from './editor/guide';
import { attachInput } from './editor/input';
import { loadModSource, mountPanel, openAsmFiles, refreshFromServer, toast } from './editor/panel';
import { PlayerOverlay } from './editor/player';
import { Store } from './editor/store';
import { View } from './editor/view';

const store = new Store();
const view = new View(document.getElementById('view') as HTMLCanvasElement, store);
const guide = new GuideOverlay(document.getElementById('app')!); // first: its key blocker runs before the others
const player = new PlayerOverlay(document.getElementById('stage')!);
const updatePanel = mountPanel(document.getElementById('panel')!, store, view, player);
attachInput(view, store);
// the game and the guide take the keyboard: pause editor shortcuts while one is shown
const pauseInput = () => (store.inputPaused = player.isOpen || guide.isOpen);
player.onOpen = () => (store.inputPaused = true);
player.onClose = () => {
  pauseInput();
  view.canvas.focus();
};
guide.onOpen = () => (store.inputPaused = true);
guide.onClose = pauseInput;
document.getElementById('p-guide')!.onclick = () => guide.open();
window.addEventListener('keydown', (e) => {
  const t = e.target as HTMLElement;
  if (e.key !== '?' || store.inputPaused || ['INPUT', 'SELECT', 'TEXTAREA'].includes(t.tagName)) return;
  e.preventDefault();
  guide.open();
});

const empty = document.getElementById('empty')!;
store.onChange(() => {
  empty.hidden = !!store.project;
  view.rebuildTerrain();
  view.requestDraw();
  updatePanel();
});

// drop a game (.json) or .asm files anywhere
window.addEventListener('dragover', (e) => e.preventDefault());
window.addEventListener('drop', async (e) => {
  e.preventDefault();
  const files = [...(e.dataTransfer?.files ?? [])];
  if (!files.length || !confirmDiscard(store, `Open ${files.map((f) => f.name).join(', ')}?`)) return;
  try {
    if (files[0].name.toLowerCase().endsWith('.json')) {
      await openGameFile(store, files[0]);
      toast(`Opened ${files[0].name}`);
    } else toast(await openAsmFiles(store, files));
    view.fitLevel();
  } catch (err) {
    toast(String(err));
  }
});
window.addEventListener('beforeunload', () => store.saveNow());

async function start() {
  // the game being edited when the page was closed, else a new game from the template
  if (store.restoreAutosave()) {
    toast(store.dirty ? `Restored "${store.name}" with its unsaved changes` : `Restored "${store.name}"`);
    // the memory layout comes from the template on disk; offline, keep the autosaved one
    await refreshFromServer(store).catch(() => {});
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
if (import.meta.env.DEV) Object.assign(window, { editor: { store, view, player, guide } });
