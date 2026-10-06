// Paths shared by the dev server (vite.config.ts) and server/index.ts.

import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';

const HERE = import.meta.dirname;
export const PACKAGE_DIR = join(HERE, '..');
/** The mod source: the template for new games and what builds use (override: THRUST_MOD_SRC). */
export const MOD_SRC = process.env.THRUST_MOD_SRC ?? join(PACKAGE_DIR, '../thrusty-levels/src');
export const DIST_DIR = join(PACKAGE_DIR, 'dist');
/** The game new games start from: the original levels (override: THRUST_TEMPLATE;
 *  remake with npm run mod-to-game -- --original <file> thrust). */
export const TEMPLATE = process.env.THRUST_TEMPLATE ?? join(PACKAGE_DIR, '../thrusty-levels/examples/template.json');

/** c64-ready's runtime assets, served by the editor under /c64/. */
const c64public = dirname(createRequire(import.meta.url).resolve('c64-ready/wasm')); // .../public/c64.wasm
export const C64_ASSETS: Record<string, { path: string; type: string }> = {
  'c64.wasm': { path: join(c64public, 'c64.wasm'), type: 'application/wasm' },
  'audio-worklet-processor.js': { path: join(c64public, 'audio-worklet-processor.js'), type: 'text/javascript' },
};
