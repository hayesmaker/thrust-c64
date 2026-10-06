// Make a game file from the mod's level files (the reverse of game-to-mod).
// With --original the levels are the original game's (the disassembly in src/),
// written into the mod's files: that is examples/template.json, which the editor
// starts new games from.
//
//   npm run mod-to-game -- [--original] <game.json> [name] [author]
//   npm run mod-to-game -- --original ../thrusty-levels/examples/template.json thrust
//
// The model code is loaded through Vite (it imports without .ts extensions).

import { readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createServer } from 'vite';
import { MOD_SRC, PACKAGE_DIR } from '../server/paths.ts';

const args = process.argv.slice(2);
const original = args[0] === '--original';
if (original) args.shift();
const [arg, name = 'thrust', author = ''] = args;
if (!arg) {
  console.error('usage: npm run mod-to-game -- [--original] <game.json> [name] [author]');
  process.exit(1);
}
const out = resolve(process.env.INIT_CWD ?? process.cwd(), arg);
const read = (dir: string) => [readFileSync(join(dir, 'levels.asm'), 'utf8'), readFileSync(join(dir, 'level_tables.asm'), 'utf8')] as const;

const vite = await createServer({ root: PACKAGE_DIR, configFile: false, server: { middlewareMode: true }, appType: 'custom', logLevel: 'error' });
try {
  const { loadProject, saveProject } = await vite.ssrLoadModule('/src/model/level.ts');
  const { GAME_FORMAT, GAME_VERSION } = await vite.ssrLoadModule('/src/editor/store.ts');
  const mod = loadProject(...read(MOD_SRC));
  if (original) {
    const orig = loadProject(...read(join(PACKAGE_DIR, '../../src')));
    mod.levels = orig.levels;
    mod.roundCycle = orig.roundCycle;
  }
  // through the mod's files, as the editor builds them, so the game's sources hold its levels
  const src = saveProject(mod, { title: name, author });
  const p = loadProject(src.levelsAsm, src.tablesAsm);
  // the same fields, in the same order, as the editor's Save (Store.toJSON)
  const game = {
    format: GAME_FORMAT,
    version: GAME_VERSION,
    name,
    author,
    levelsAsm: p.levelsAsm,
    tablesAsm: p.tablesAsm,
    levels: p.levels,
    roundCycle: p.roundCycle,
    level: 0,
  };
  writeFileSync(out, JSON.stringify(game));
  console.log(`wrote ${out}: ${original ? 'the original levels' : 'the mod\'s levels'} in the mod's level files`);
} finally {
  await vite.close();
}
