// Editor state: the project, current level, selection, undo/redo, autosave.

import { type Level, type Project, decodeLevel, levelRows, loadProject } from '../model/level';
import { type Layout } from '../model/validate';

export type Side = 'left' | 'right';

export type Selection =
  | { kind: 'point'; side: Side; index: number }
  | { kind: 'object'; index: number }
  | { kind: 'restart'; index: number };

export const sameSelection = (a: Selection | null, b: Selection | null): boolean =>
  !!a && !!b && a.kind === b.kind && a.index === b.index && (a.kind !== 'point' || a.side === (b as typeof a).side);

const AUTOSAVE_KEY = 'thrust-level-editor:v1';
const HISTORY_LIMIT = 200;
/** Extra rows decoded below the end of the walls, so walls can be extended. */
export const ROWS_MARGIN = 300;

interface Saved {
  sourceName: string;
  sourceHash?: string | null;
  layout?: Layout | null;
  levelsAsm: string;
  tablesAsm: string;
  levels: Level[];
  level: number;
}

export class Store {
  project: Project | null = null;
  sourceName = '';
  level = 0;
  selection: Selection | null = null;
  hover: Selection | null = null;
  /** Dragged/added objects rest on the terrain (Alt inverts while dragging). */
  snapObjects = true;
  /** Hash of the mod source this project was loaded from (for safe saving). */
  sourceHash: string | null = null;
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

  get current(): Level | null {
    return this.project?.levels[this.level] ?? null;
  }

  onChange(fn: () => void): void {
    this.listeners.add(fn);
  }

  /** Recompute derived data and notify (call after every change). */
  changed(save = true): void {
    const l = this.current;
    this.decoded = l ? decodeLevel(l, levelRows(l, ROWS_MARGIN)) : { left: [], right: [] };
    for (const fn of this.listeners) fn();
    if (save) this.scheduleSave();
  }

  load(project: Project, sourceName: string, sourceHash: string | null = null): void {
    this.project = project;
    this.sourceName = sourceName;
    this.sourceHash = sourceHash;
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
    return JSON.stringify({ levels: this.project!.levels, level: this.level });
  }

  private restore(s: string): void {
    const { levels, level } = JSON.parse(s);
    this.project!.levels = levels;
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
      localStorage.setItem(AUTOSAVE_KEY, JSON.stringify(this.toJSON()));
    } catch {
      // storage full or blocked: autosave is a convenience only
    }
  }

  toJSON(): Saved {
    const p = this.project!;
    return { sourceName: this.sourceName, sourceHash: this.sourceHash, layout: this.layout, levelsAsm: p.levelsAsm, tablesAsm: p.tablesAsm, levels: p.levels, level: this.level };
  }

  /** Load a saved project (autosave or a JSON file). */
  fromJSON(s: Saved): void {
    const p = loadProject(s.levelsAsm, s.tablesAsm);
    p.levels = s.levels;
    this.layout = s.layout ?? null;
    this.load(p, s.sourceName, s.sourceHash ?? null);
    this.level = s.level ?? 0;
    this.changed(false);
  }

  restoreAutosave(): boolean {
    try {
      const raw = localStorage.getItem(AUTOSAVE_KEY);
      if (!raw) return false;
      this.fromJSON(JSON.parse(raw));
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
