// Game files: each game is one JSON file the user keeps wherever they like.
//
// Where the browser has the File System Access API (Chrome, Edge), Save
// writes back to the file the game was opened from or last saved to.
// Elsewhere Save downloads <name>.json and Open uses a file input.

import { download } from './export';
import type { Store } from './store';

interface FileHandle {
  readonly name: string;
  getFile(): Promise<File>;
  createWritable(): Promise<{ write(data: string): Promise<void>; close(): Promise<void> }>;
}
interface PickerOptions {
  suggestedName?: string;
  types?: { description: string; accept: Record<string, string[]> }[];
}
interface Pickers {
  showSaveFilePicker(o: PickerOptions): Promise<FileHandle>;
  showOpenFilePicker(o: PickerOptions): Promise<FileHandle[]>;
}

const TYPES = [{ description: 'Thrust game', accept: { 'application/json': ['.json'] } }];
const pickers = (): Pickers | null => ('showSaveFilePicker' in window ? (window as unknown as Pickers) : null);
const aborted = (e: unknown) => e instanceof DOMException && e.name === 'AbortError';

/** The file the current game lives in (lost on reload: Save asks again). */
let handle: FileHandle | null = null;

/** File name for a game name: "My Game!" -> "my-game.json". */
export function fileNameFor(name: string): string {
  const slug = name
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return `${slug || 'thrust-game'}.json`;
}

/** Save the game. `as`: always ask where. Returns the file name, or null
 *  when the user cancelled. */
export async function saveGame(store: Store, as = false): Promise<string | null> {
  if (!store.project) return null;
  const text = JSON.stringify(store.toJSON());
  const p = pickers();
  if (!p) {
    const name = fileNameFor(store.name);
    download(name, text, 'application/json');
    store.markSaved(name);
    return name;
  }
  if (as || !handle) {
    try {
      handle = await p.showSaveFilePicker({ suggestedName: as ? fileNameFor(store.name) : (store.fileName ?? fileNameFor(store.name)), types: TYPES });
    } catch (e) {
      if (aborted(e)) return null;
      throw e;
    }
  }
  const w = await handle.createWritable();
  await w.write(text);
  await w.close();
  store.markSaved(handle.name);
  return handle.name;
}

/** Ask before throwing away unsaved changes. */
export function confirmDiscard(store: Store, what: string): boolean {
  return !store.dirty || confirm(`${what}\n\n"${store.name}" has unsaved changes. They will be lost.`);
}

/** Open a game file (from a picker, the file input or a drop). */
export async function openGameFile(store: Store, file: File, from: FileHandle | null = null): Promise<void> {
  const text = await file.text();
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    throw new Error(`${file.name} is not a JSON file`);
  }
  store.fromJSON(data as Parameters<Store['fromJSON']>[0], file.name);
  handle = from;
}

/** Show the open dialog. Returns false when the browser has no picker
 *  (use a file input instead). */
export async function pickGameFile(store: Store): Promise<boolean> {
  const p = pickers();
  if (!p) return false;
  try {
    const [h] = await p.showOpenFilePicker({ types: TYPES });
    await openGameFile(store, await h.getFile(), h);
  } catch (e) {
    if (!aborted(e)) throw e;
  }
  return true;
}

/** The game no longer belongs to a file (new game, imported .asm). */
export function forgetFile(): void {
  handle = null;
}
