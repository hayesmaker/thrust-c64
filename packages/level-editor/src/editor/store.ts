// Editor state: the game, current level, selection, undo/redo, autosave.
//
// A game is one JSON file (GameFile): the levels plus the levels.asm /
// level_tables.asm text they patch. The mod source on disk is only the
// template new games start from; the editor never writes it.

import { type Round } from '../model/door';
import { type Level, type Project, decodeLevel, levelRows, loadProject, upgradeLevels } from '../model/level';
import { snapObject } from '../model/objects';
import { type Layout } from '../model/validate';

export type Side = 'left' | 'right';

export type Selection =
  | { kind: 'point'; side: Side; index: number }
  | { kind: 'object'; index: number }
  | { kind: 'restart'; index: number }
  /** door handle: index -1 = the door (top tab), 0.. = a door row */
  | { kind: 'door'; index: number };

export const sameSelection = (a: Selection | null, b: Selection | null): boolean =>
  !!a && !!b && a.kind === b.kind && a.index === b.index && (a.kind !== 'point' || a.side === (b as typeof a).side);

const AUTOSAVE_KEY = 'thrust-level-editor:v1';
const HISTORY_LIMIT = 200;
/** Extra rows decoded below the end of the walls, so walls can be extended. */
export const ROWS_MARGIN = 300;

export const GAME_FORMAT = 'thrust-level-editor/game';
/** 2: doors, level rules and the round cycle */
export const GAME_VERSION = 2;
export const DEFAULT_NAME = 'my thrust game';

/** A saved game (JSON file). Older files (no format) are read too. */
export interface GameFile {
  format?: string;
  version?: number;
  name?: string;
  levelsAsm: string;
  tablesAsm: string;
  levels: Level[];
  /** version 2 */
  roundCycle?: Round[];
  level?: number;
  /** autosave only */
  layout?: Layout | null;
  fileName?: string | null;
  clean?: boolean;
  /** older files */
  sourceName?: string;
}

export class Store {
  project: Project | null = null;
  /** Game name; the JSON file is named after it. */
  name = DEFAULT_NAME;
  /** File the game was opened from or last saved to (null: never saved). */
  fileName: string | null = null;
  level = 0;
  selection: Selection | null = null;
  hover: Selection | null = null;
  /** Dragged/added objects rest on the terrain (Alt inverts while dragging). */
  snapObjects = true;
  /** Door opening shown in the view (0 = closed). */
  doorPreview = 0;
  /** Set while the emulator has the keyboard: editor shortcuts are off. */
  inputPaused = false;
  /** Where the mod keeps level data (from the server; null = original layout). */
  layout: Layout | null = null;
  /** Decoded wall X per row for the current level (mod 256). */
  decoded: { left: number[]; right: number[] } = { left: [], right: [] };

  private undoStack: string[] = [];
  private redoStack: string[] = [];
  private listeners = new Set<() => void>();
  private saveTimer = 0;
  /** The game as last opened or saved, to tell unsaved changes. */
  private savedState = '';

  get current(): Level | null {
    return this.project?.levels[this.level] ?? null;
  }

  onChange(fn: () => void): void {
    this.listeners.add(fn);
  }

  /** Recompute derived data and notify (call after every change). */
  changed(save = true): void {
    this.decode();
    this.notify(save);
  }

  /** Call after editing a wall (instead of changed()). With snapping on,
   *  objects that were resting on the terrain before the edit stay resting
   *  on it: they follow the floor or ceiling as it moves. */
  terrainChanged(): void {
    const l = this.current;
    if (!l || !this.snapObjects) return this.changed();
    const before = this.decoded;
    const resting = l.objects.map((o) => {
      const s = snapObject(o, before.left, before.right);
      return !!s && s.x === o.x && s.y === o.y;
    });
    this.decode();
    l.objects = l.objects.map((o, i) => {
      if (!resting[i]) return o;
      const s = snapObject(o, this.decoded.left, this.decoded.right);
      return s && (s.x !== o.x || s.y !== o.y) ? { ...o, ...s } : o;
    });
    this.notify(true);
  }

  private decode(): void {
    const l = this.current;
    this.decoded = l ? decodeLevel(l, levelRows(l, ROWS_MARGIN)) : { left: [], right: [] };
  }

  private notify(save: boolean): void {
    for (const fn of this.listeners) fn();
    if (save) this.scheduleSave();
  }

  /** Start editing a game. `fileName` null = not saved anywhere yet. */
  load(project: Project, name: string, fileName: string | null = null): void {
    this.project = project;
    this.name = name;
    this.fileName = fileName;
    this.savedState = this.state();
    this.level = 0;
    this.selection = null;
    this.undoStack = [];
    this.redoStack = [];
    this.changed();
  }

  setLevel(n: number): void {
    this.level = n;
    this.selection = null;
    this.hover = null;
    this.changed();
  }

  /** Snapshot before an edit (one per user gesture). */
  checkpoint(): void {
    if (!this.project) return;
    this.undoStack.push(this.snapshot());
    if (this.undoStack.length > HISTORY_LIMIT) this.undoStack.shift();
    this.redoStack = [];
  }

  /** Drop the last checkpoint if the gesture changed nothing. */
  cancelCheckpointIfUnchanged(): void {
    if (this.undoStack[this.undoStack.length - 1] === this.snapshot()) this.undoStack.pop();
  }

  canUndo(): boolean {
    return this.undoStack.length > 0;
  }

  canRedo(): boolean {
    return this.redoStack.length > 0;
  }

  undo(): void {
    const s = this.undoStack.pop();
    if (!s) return;
    this.redoStack.push(this.snapshot());
    this.restore(s);
  }

  redo(): void {
    const s = this.redoStack.pop();
    if (!s) return;
    this.undoStack.push(this.snapshot());
    this.restore(s);
  }

  private snapshot(): string {
    return JSON.stringify({ levels: this.project!.levels, roundCycle: this.project!.roundCycle, level: this.level });
  }

  private restore(s: string): void {
    const { levels, roundCycle, level } = JSON.parse(s);
    this.project!.levels = levels;
    this.project!.roundCycle = roundCycle;
    this.level = level;
    this.selection = null;
    this.changed();
  }

  // ---- persistence -------------------------------------------------------

  private scheduleSave(): void {
    clearTimeout(this.saveTimer);
    this.saveTimer = window.setTimeout(() => this.saveNow(), 400);
  }

  saveNow(): void {
    if (!this.project) return;
    try {
      const s: GameFile = { ...this.toJSON(), layout: this.layout, fileName: this.fileName, clean: !this.dirty };
      localStorage.setItem(AUTOSAVE_KEY, JSON.stringify(s));
    } catch {
      // storage full or blocked: autosave is a convenience only
    }
  }

  private state(): string {
    return this.project ? JSON.stringify([this.name, this.project.levels, this.project.roundCycle]) : '';
  }

  /** The game differs from the file it was opened from or saved to (or
   *  was never saved). */
  get dirty(): boolean {
    return !!this.project && this.state() !== this.savedState;
  }

  /** The game as a JSON file. */
  toJSON(): GameFile {
    const p = this.project!;
    return {
      format: GAME_FORMAT,
      version: GAME_VERSION,
      name: this.name,
      levelsAsm: p.levelsAsm,
      tablesAsm: p.tablesAsm,
      levels: p.levels,
      roundCycle: p.roundCycle,
      level: this.level,
    };
  }

  setName(name: string): void {
    this.name = name;
    this.notify(true);
  }

  /** Call after writing toJSON() to `fileName`. */
  markSaved(fileName: string): void {
    this.fileName = fileName;
    this.savedState = this.state();
    this.notify(true);
  }

  /** Open a game file. Throws if it is not one. */
  fromJSON(s: GameFile, fileName: string | null = null): void {
    if (!s || typeof s !== 'object' || typeof s.levelsAsm !== 'string' || typeof s.tablesAsm !== 'string' || !Array.isArray(s.levels))
      throw new Error('not a Thrust level editor game file');
    if (s.format && s.format !== GAME_FORMAT) throw new Error(`unknown format "${s.format}"`);
    if ((s.version ?? 1) > GAME_VERSION) throw new Error('made by a newer version of the editor');
    const p = loadProject(s.levelsAsm, s.tablesAsm);
    if (s.levels.length !== p.levels.length) throw new Error(`${s.levels.length} levels, expected ${p.levels.length}`);
    p.levels = upgradeLevels(p, s.levels);
    if (Array.isArray(s.roundCycle) && s.roundCycle.length) p.roundCycle = s.roundCycle;
    const name = s.name ?? fileName?.replace(/\.json$/i, '') ?? DEFAULT_NAME;
    this.load(p, name, fileName);
    this.level = Math.min(Math.max(0, s.level ?? 0), p.levels.length - 1);
    this.changed(false);
  }

  /** Restore the game being edited when the page was closed. */
  restoreAutosave(): boolean {
    try {
      const raw = localStorage.getItem(AUTOSAVE_KEY);
      if (!raw) return false;
      const s: GameFile = JSON.parse(raw);
      this.fromJSON(s, s.fileName ?? null);
      this.layout = s.layout ?? null;
      if (!s.clean) this.savedState = '';
      this.changed(false);
      return true;
    } catch {
      return false;
    }
  }

  clearAutosave(): void {
    try {
      localStorage.removeItem(AUTOSAVE_KEY);
    } catch {
      // ignore
    }
  }
}
