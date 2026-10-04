import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { beforeAll, describe, expect, it } from 'vitest';
import { fileNameFor } from '../src/editor/files';
import { DEFAULT_NAME, GAME_FORMAT, Store } from '../src/editor/store';
import { loadProject } from '../src/model/level';

const ROOT = join(import.meta.dirname, '../../..');
const read = (p: string) => readFileSync(join(ROOT, p), 'utf8');
const LEVELS = read('packages/thrusty-levels/src/levels.asm');
const TABLES = read('packages/thrusty-levels/src/level_tables.asm');

beforeAll(() => {
  // the store autosaves on a timer; no DOM here
  Object.assign(globalThis, { window: { setTimeout: () => 0 } });
});

function template(): Store {
  const s = new Store();
  s.load(loadProject(LEVELS, TABLES), DEFAULT_NAME);
  return s;
}

const edit = (s: Store) => {
  s.checkpoint();
  s.current!.gravity++;
  s.changed();
};

describe('game files', () => {
  it('a new game from the template is unchanged and not saved anywhere', () => {
    const s = template();
    expect(s.dirty).toBe(false);
    expect(s.fileName).toBeNull();
  });

  it('tracks unsaved changes against the last save', () => {
    const s = template();
    edit(s);
    expect(s.dirty).toBe(true);
    s.markSaved('mine.json');
    expect(s.dirty).toBe(false);
    expect(s.fileName).toBe('mine.json');
    s.undo();
    expect(s.dirty).toBe(true); // differs from what was saved
    s.redo();
    expect(s.dirty).toBe(false);
    s.setName('renamed');
    expect(s.dirty).toBe(true);
  });

  it('saves and opens a game', () => {
    const a = template();
    edit(a);
    a.setName('Big caves');
    a.setLevel(3);
    const file = JSON.parse(JSON.stringify(a.toJSON()));
    expect(file.format).toBe(GAME_FORMAT);
    expect(file.version).toBe(1);
    const b = new Store();
    b.fromJSON(file, 'big-caves.json');
    expect(b.name).toBe('Big caves');
    expect(b.fileName).toBe('big-caves.json');
    expect(b.level).toBe(3);
    expect(b.project!.levels).toEqual(a.project!.levels);
    expect(b.dirty).toBe(false);
  });

  it('opens files from before the format field, named after the file', () => {
    const { format, version, name, ...old } = template().toJSON();
    void format, version, name;
    const s = new Store();
    s.fromJSON({ ...old, sourceName: 'packages/thrusty-levels/src' }, 'old-levels.json');
    expect(s.name).toBe('old-levels');
  });

  it('refuses files that are not games', () => {
    const s = new Store();
    const good = template().toJSON();
    expect(() => s.fromJSON({ hello: 1 } as never)).toThrow(/not a Thrust/);
    expect(() => s.fromJSON({ ...good, format: 'something-else' })).toThrow(/unknown format/);
    expect(() => s.fromJSON({ ...good, version: 99 })).toThrow(/newer version/);
    expect(() => s.fromJSON({ ...good, levels: good.levels.slice(1) })).toThrow(/expected 6/);
    expect(s.project).toBeNull();
  });

  it('names files after the game', () => {
    expect(fileNameFor('My Thrust game!')).toBe('my-thrust-game.json');
    expect(fileNameFor('  ')).toBe('thrust-game.json');
  });
});
