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
* Doors are code (`tick_door_logic`), not data: levels 3-5 only.
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
- [ ] Scaffold `packages/level-editor/` (Vite + TS + vitest).
- [ ] Export the 6 original levels to JSON (`tools/level2json.py`, reading the PRG
      + `.sym` like `terrainview.py`) as fixtures and starter templates.
- [ ] Python reference dump of decoded wall X per row for each level (golden data).

### Phase 1 - terrain model (no UI)
- [ ] TS port of the decoder (`decodeWall(counts, steps, startX) → x[]`).
- [ ] Encoder: vertices → A/B (C/D) tables, with staircase/Bresenham splitting.
- [ ] Importer: tables → vertices.
- [ ] Unit tests (vitest): decoder matches golden dumps; round trip for all levels;
      long runs, wrap-around, steep slopes, ledges.
- [ ] Asm reader/writer: parse labelled `.byte` blocks in `levels.asm` /
      `level_tables.asm` into a level project, and patch them back in place.
      Test: parse → write with no edits reproduces both files byte for byte.

### Phase 2 - editor UI (MVP: "drag points, see it, spit out tables")
- [ ] Canvas view in game aspect (2:1), zoom + pan, grid snapping to world units,
      rulers in hex and decimal (like terrainview).
- [ ] Render rock by filling each row left of the left wall / right of the right
      wall from the decoded X arrays — the same thing the game draws, so wrap,
      crossings and closed caves look right.
- [ ] Wall vertices as draggable handles; click on segment = insert, del/right-click
      = remove; constrain row order; Shift = lock to a pure slope (0, ±1, ±2...).
- [ ] Live redraw on every drag (decode is cheap: a few thousand rows).
- [ ] Overlay: screen window (80 × 92) at the start position, to judge scale.
- [ ] Side panel: live A/B/C/D tables, entry counts, bytes used.
- [ ] Load: open/drop `levels.asm` + `level_tables.asm` (later: fetched from the API).
- [ ] "Export" button: the terrain `.byte` lines for the level (copy to clipboard),
      plus "download patched levels.asm".
- [ ] Undo/redo, autosave to localStorage, save/load JSON.

### Phase 3 - objects, restart points, level settings
- [ ] Object palette (guns ×4, fuel, pod stand, generator, switches) with
      `obj_type_width/height` boxes; drag to place; snap Y to the surface.
- [ ] Gun parameter editor: angle dial (0-28) + spread (1/3/7/15), shown as a cone.
- [ ] Restart points: drag the ship marker; window auto-computed (editable).
- [ ] Level settings: gravity (FRAC), the 6 colours (C64 palette picker), and
      render in those colours.
- [ ] Validation panel: object 0 is pod stand, ≤ 32 objects, fuel in first 12,
      table ≤ 255 entries, run ≤ 254, objects inside rock, start point inside rock,
      door levels (3-5) warning.
- [ ] Export all object/restart/table blocks; level switcher for levels 0-5.
- [ ] Memory budget meter against the free regions in level_format.md.

### Phase 4 - Node build API
- [ ] `editor/server`: small Node (http or Fastify) service, localhost only.
- [ ] `POST /build` with the level project JSON →
      copy `packages/thrusty-levels/src` into a temp dir, write generated `levels.asm`
      (+ `level_tables.asm` when settings/restarts change), run
      `java -jar /opt/KickAss.jar thrust.asm -vicesymbols -symbolfile`,
      return `{ id, ok, log, errors[] }`. Never write into `packages/thrusty-levels/src`
      unless asked (separate `POST /save` endpoint with a confirm in the UI).
- [ ] `GET /builds/:id.prg` (+ `.sym`, `.vs`) with CORS for c64-ready.
- [ ] Map KickAss errors (file:line) back to the level/table that caused them.
- [ ] `GET /source` returns the current `levels.asm` + `level_tables.asm`, so the
      editor opens the real mod files without a file picker.

### Phase 5 - run in c64-ready
- [ ] Quick path: "Play" opens `http://localhost:<c64-ready>/?game=http://localhost:<api>/builds/<id>.prg`.
- [ ] Better: embed `C64Player` from the c64-ready package in an editor panel and
      `loadGameData()` the built PRG — build-and-play without leaving the page.
- [ ] "Test this level": after boot, use the `.sym` to poke `level_number`
      (and optionally a restart point / infinite fuel) with `cpuWrite`, so play
      starts on the edited level. May need a small debug hook in the mod source.
- [ ] Optional: watch mode — rebuild on edit with debounce, hot-reload the emulator.

## After the MVP
- [ ] New levels (7+): pointer/lookup table entries, `cmp #$06`, placement in
      `$1000-$1FFF`, colours/gravity — see "Adding levels" in level_format.md.
- [ ] Door editor (needs generated `tick_door_logic` routines).
