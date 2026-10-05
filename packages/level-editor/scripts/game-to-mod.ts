// Make a saved game the mod's template: writes its levels into
// packages/thrusty-levels/src/levels.asm + level_tables.asm (THRUST_MOD_SRC
// overrides), the same way the editor's "Assembler files" downloads do.
//
//   npm run game-to-mod -- template.json
//
// The model code is loaded through Vite (it imports without .ts extensions).

import { readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createServer } from 'vite';
import { MOD_SRC, PACKAGE_DIR } from '../server/paths.ts';

const arg = process.argv[2];
if (!arg) {
  console.error('usage: npm run game-to-mod -- <game.json>');
  process.exit(1);
}
const game = JSON.parse(readFileSync(resolve(process.env.INIT_CWD ?? process.cwd(), arg), 'utf8'));

const vite = await createServer({ root: PACKAGE_DIR, configFile: false, server: { middlewareMode: true }, appType: 'custom', logLevel: 'error' });
try {
  const { loadProject, saveProject, upgradeLevels } = await vite.ssrLoadModule('/src/model/level.ts');
  if (typeof game.levelsAsm !== 'string' || typeof game.tablesAsm !== 'string' || !Array.isArray(game.levels))
    throw new Error(`${arg} is not a Thrust level editor game file`);
  const files = { levelsAsm: join(MOD_SRC, 'levels.asm'), tablesAsm: join(MOD_SRC, 'level_tables.asm') };
  const disk = { levelsAsm: readFileSync(files.levelsAsm, 'utf8'), tablesAsm: readFileSync(files.tablesAsm, 'utf8') };
  if (game.levelsAsm !== disk.levelsAsm || game.tablesAsm !== disk.tablesAsm)
    console.warn('note: the game was made from a different version of the mod files; its level data replaces theirs');
  // patch the mod's current files, so hand edits elsewhere in them are kept
  const project = loadProject(disk.levelsAsm, disk.tablesAsm);
  if (game.levels.length !== project.levels.length) throw new Error(`${game.levels.length} levels, expected ${project.levels.length}`);
  // older games: doors / rules from the game's own sources
  project.levels = upgradeLevels(loadProject(game.levelsAsm, game.tablesAsm), game.levels);
  if (Array.isArray(game.roundCycle) && game.roundCycle.length) project.roundCycle = game.roundCycle;
  const out = saveProject(project, {
    ...(typeof game.name === 'string' ? { title: game.name } : {}),
    author: typeof game.author === 'string' ? game.author : '',
  });
  for (const k of ['levelsAsm', 'tablesAsm'] as const) {
    if (out[k] === disk[k]) console.log(`unchanged ${files[k]}`);
    else {
      writeFileSync(files[k], out[k]);
      console.log(`wrote     ${files[k]}`);
    }
  }
} finally {
  await vite.close();
}
