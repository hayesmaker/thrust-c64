# Thrust level editor - plan

A browser editor for Thrust (C64) levels: drag wall points and objects, see the
level redraw live, export the `.byte` tables. Later: a local Node API that builds
a PRG with KickAssembler and runs it in c64-ready.

## Decisions (2026-10-04)

* Layout: `packages/` in this repo. `packages/thrusty-levels/` (moved from the
  repo root) is the mod source; `packages/level-editor/` is the editor
  (+ `server/` for the build API later).
* Stack: TypeScript + canvas 2D, built with Vite (same toolchain as c64-ready).
* MVP scope: edit the **existing 6 levels** in
  `packages/thrusty-levels/src/levels.asm` and `level_tables.asm`. New levels
  (pointer tables, `cmp #$06`, `$1000-$1FFF` placement) come after the MVP.
* Read/write model: parse the two files and replace only the `.byte` lines
  under known labels (`terrain_data_level_N_A..D`, `level_N_obj_*`,
  `level_N_reset_data`, `level_reset_data_sizes`, gravity, colours, and
  `level_reset_ptr2_table_*` offsets when restart counts change). Comments and
  everything else in the hand-edited files stay as they are. No markers needed.

## Facts the editor has to respect

From `docs/level_format.md` and `tools/terrainview.py`:

* Terrain is 4 tables per level: A/B = left wall (run length, X step per row),
  C/D = right wall. Left wall starts at X 0, right at X 255. X is 8-bit and wraps.
* Decoder (`terrainview.decode`): starts at index 1 with count `$FF`; on each
  count reaching 0 it reads the next entry; **a count of `$FF` ends the wall**
  (X then stays fixed). So entry 0 is a dummy, entry 1 is the sky run, and the
  longest real run is 254 rows. Steps are signed bytes.
* Any integer step works; slopes steeper than ±1 need staircases (alternating
  1 row ±1 / k rows 0). ≤ ~255 entries per table.
* Aspect: 1 X unit = 4 px, 1 row = 2 px (2:1). World Y is 16-bit; maps start at
  row `$100`; ship start X `$6C` Y `$191`.
* Objects: X, Y, Y_EXT, type (0-8, `$FF` terminated), gun param (angle bits 2-4,
  spread bits 0-1). Object 0 = pod stand, ≤ 32 objects, fuel among the first 12.
* Restart points: 6 rows × n (ship Y_EXT, ship Y, window X, window Y_EXT,
  window Y, ship X). Window ≈ ship − (`$16`, `$64`).
* Doors were code (`tick_door_logic`), levels 3-5 only; thrusty-levels now has
  them as per-level tables (see Doors and rules below).
* c64-ready: `?game=<http url>` loads a PRG from any URL; the npm package
  exports `C64Player` with `loadGameData()` and `cpuWrite()` for embedding.

## Core design: points ↔ runs

The editor stores each wall as a list of vertices `(row, x)` with strictly
increasing rows. The tables are generated, never edited by hand:

* Segment `(r0,x0) → (r1,x1)`, `dy = r1−r0`, `dx = x1−x0` (shortest way round
  the wrap, or as drawn):
  * `dy = 1` → one row of step `dx` (ledge).
  * `dx % dy == 0` → one run of `dy` rows, step `dx/dy`.
  * otherwise → spread `dx` over `dy` rows Bresenham-style: steps `q` and `q+1`
    (or `0`/`±1` for steep segments), merging equal neighbours into runs.
* Split runs longer than 254 rows. Prepend `dummy, $FF sky, n rows`; append the
  `$FF` terminator.
* Import is the reverse: decode tables → one vertex per run boundary. This
  lets the 6 original levels (and the hand-edited `packages/thrusty-levels/src/levels.asm`)
  load into the editor.
* Golden test: import → export must reproduce the original tables byte for byte
  (where the original runs are already "canonical"), and decoded wall X per row
  must match `terrainview.decode` exactly for all 6 levels.

## Phases and todos

### Phase 0 - setup
- [x] Move `thrusty-levels/` to `packages/thrusty-levels/` (build verified unchanged).
- [x] Scaffold `packages/level-editor/` (Vite + TS + vitest).
- [x] Export the 6 original levels to JSON (`tools/level2json.py`, reading the PRG
      + `.sym` like `terrainview.py`) -> `test/fixtures/original_levels.json`.
- [x] Python reference dump of decoded wall X per row for each level (in the same JSON).

### Phase 1 - terrain model (no UI)
- [x] TS port of the decoder (`decodeWall(counts, steps, startX) → x[]`).
- [x] Encoder: vertices → A/B (C/D) tables, with staircase/Bresenham splitting.
- [x] Importer: tables → vertices (simplified: staircases become one steep segment,
      only where the decoded rows stay identical).
- [x] Unit tests (vitest): decoder matches golden dumps; round trip for all levels;
      long runs, wrap-around, steep slopes, ledges.
- [x] Asm reader/writer: parse labelled `.byte` blocks in `levels.asm` /
      `level_tables.asm` into a level project, and patch them back in place.
      Test: parse → write with no edits reproduces both files byte for byte.

- [x] End-to-end test: edit level 0, build a temp copy with KickAss, read the PRG
      back with `level2json.py` and compare (`test/kickass.test.ts`).

### Phase 2 - editor UI (MVP: "drag points, see it, spit out tables") - done
- [x] Canvas view in game aspect (2:1), zoom + pan, rulers in hex and decimal,
      grid, X wrap seams; the world repeats horizontally.
- [x] Rock drawn row by row from the decoded wall arrays (the game's rule).
- [x] Draggable wall points; click a line = insert (on the line, no jump);
      right-click / Del = remove; rows clamped between neighbours;
      Shift = whole step per row; arrows nudge.
- [x] Uneven segments (staircases) drawn dashed, with their table cost shown.
- [x] Live redraw while dragging.
- [x] Overlay: objects, restart points, screen window (window Y + $38, 80 × 92).
- [x] Side panel: selected point (row/X inputs), live A/B/C/D tables, entry
      counts, bytes vs original, >255 entries warning.
- [x] Load: dev-server `GET /api/source` (read-only, packages/thrusty-levels/src),
      "Open .asm files", drag and drop.
- [x] Export: copy terrain `.byte` lines; download patched `levels.asm` /
      `level_tables.asm` (only edited blocks change).
- [x] Undo/redo, autosave to localStorage, save/open project JSON, revert level.
- [x] Verified in headless Chrome: drag/insert/undo/level switch, autosave across
      reload, and downloaded files built with KickAss decode to exactly what
      the editor shows.

### Phase 3 - objects, restart points, level settings - done
- [x] Object palette (all 9 types) with `obj_type_width/height` boxes; drag to
      place; per-type snap to the terrain (rules measured from the originals:
      every original object sits exactly where its rule puts it); Alt = free.
- [x] Fuel is inserted before guns, the pod stand at 0; reorder ▲▼ and "Sort".
- [x] Gun editor: direction (8 bases) + spread; firing arc drawn in the view
      (base .. base + mask + 3 of 32, from the bullet start offset).
- [x] Restart points: drag the ship; the window follows; "centre window"
      (ship − $16, $64); kept in depth order; the start can't be deleted.
- [x] Level settings: gravity and the 6 colours (C64 palette); terrain and
      objects render in the level's colours.
- [x] Checks panel (click to select): pod stand first, ≤ 32 objects, fuel in the
      first 12, generator present, objects not resting on terrain, restarts out
      of order or in rock, > 255 table entries, open cave bottom, door levels.
      The original levels give no errors or warnings.
- [x] Door overlay for levels 3-5 (hard-coded in `tick_door_logic`).
- [x] Memory meter: all level data vs ~1240 bytes (892 original + 348 free).
- [x] Browser test: objects/restarts/gravity/colours exported, built with
      KickAss and read back from the PRG all match; other levels untouched.

### Phase 4 - Node build API - done
- [x] `packages/level-editor/server/api.ts`: dependency-free Node handler, used as
      middleware by the Vite dev server and by `server/index.ts` (standalone,
      serves `dist/` + the API on 127.0.0.1:5180, `npm run serve`).
- [x] `GET /api/source` (+ hash). (`PUT /api/source` with backups was removed:
      the mod is a read-only template, games are JSON files; see below.)
- [x] `POST /api/build`: temp copy of `packages/thrusty-levels/src` + the two
      generated files, KickAss, `{ ok, errors[], log, files }`; builds are queued
      and the last 12 kept (in the system temp dir).
- [x] `GET /api/builds/<id>/<file>`: thrust.prg / play.prg / .sym / .vs / log, with
      CORS (+ Private-Network) so c64-ready on another origin can load them.
- [x] KickAss errors parsed and shown with the table label of the line.
- [x] `THRUST_MOD_SRC` overrides the mod path (used by tests).

### Phase 5 - run in c64-ready - done
- [x] `c64-ready` (npm, 2.5.0) embedded: `C64Player` + `CanvasRenderer` in an
      overlay; a fresh player per run (autorun is reliable from a cold start);
      `c64.wasm` and the audio worklet served under `/c64/` (dev middleware,
      copied into `dist/c64/` by the build).
- [x] Keyboard input mode (Thrust has no joystick code); editor shortcuts are
      paused while the game is shown. Rebuild / Restart / Sound / Close.
- [x] "Start the game on this level": the server patches `lda #$ff` before
      `sta level_number` in the new-game code (found via the .sym) to level − 1
      in `play.prg`. Verified: after Space, `level_number` in RAM is the level.
- [x] "Open in c64-ready" (`?game=<build URL>`, base URL configurable) and
      "Download PRG".
- [ ] Optional: watch mode (rebuild on edit, debounced).
- [ ] Optional: cheats for testing (infinite fuel/lives) via more PRG patches.

### Memory (after phase 5) - done
- [x] thrusty-levels: `levels.asm` moved to `$1000-$1FFF` (4 KB; was ~1.1 KB in the
      main block), layout checks as `.errorif` (a failed `.assert` still writes
      the PRG). Verified in the emulator: RAM at `$1000` matches the PRG after
      start-up and all six levels play.
- [x] Server: failed `.assert`s count as build errors; `/api/source` reports the
      levels area (`LEVELS_AREA_START/END` in thrust.asm).
- [x] Editor: rough meter per area (levels area / main block), amber "tight"
      (< 10% or 64 bytes free) and red "over" states, banner by Build & play,
      Checks entries, toast when it gets worse.
- [x] Python tools map `$0801-$2FFF` in place, so they read the new layout.
- [x] The layout always comes from the server, also after restoring an autosave
      (autosaves made before the change had none); a toast says when the mod
      source changed on disk since the project was loaded, or when the server
      is too old to report the layout.

### Objects follow the terrain - done
- [x] With snapping on, objects resting on the terrain before a wall edit are
      re-snapped after it (drag, insert, delete, nudge, typed row/X); objects
      placed freely stay put. "Snap all to terrain" fixes a whole level.

### Objects drawn as sprites - done
- [x] Objects are drawn with the game's sprites (frames $22-$2E, generated
      into `src/model/sprites.ts` by `scripts/gen-sprites.ts`) at the game's
      position, instead of their collision boxes (fuel's box reaches 3 rows
      below the sprite). One colour per type, or the level's game colours
      (View option). Selection and hit testing use the visible sprite bounds.

### Games are JSON files - done
- [x] The mod source is a read-only template (no more "Save to mod source",
      `PUT /api/source` or backups). A game = one JSON file
      (`format: thrust-level-editor/game`, version 1, name, levelsAsm,
      tablesAsm, levels); old "Save JSON" files still open.
- [x] Game section: name, file + unsaved-changes status, Save (Ctrl+S), Save
      as, Open (Ctrl+O, or drop), New from template; confirm before discarding
      unsaved changes. File System Access API where available (Save rewrites
      the same file), download / file input elsewhere.
- [x] Autosave keeps the game, its file name and whether it was saved.

## After the MVP
- [ ] New levels (7+): pointer/lookup table entries, `cmp #$06`, placement in
      `$1000-$1FFF`, colours/gravity — see "Adding levels" in level_format.md.
- [x] Door editor and rules (2026-10-05): `tick_door_logic` in thrusty-levels is
      table driven (`level_door_*`, `level_N_door_x`): one door per level, left
      or right wall, per-row shape, slide or reveal, open time. Reverse gravity /
      invisible landscape come from a round cycle table plus per-level rules
      (`round_cycle_*`, `level_rule_*`, `apply_level_rules`). Editor: Door and
      Rules panel sections, door tab / row handles on the map, game files v2
      (v1 files and older mod sources get the original doors added).
