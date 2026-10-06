# Thrust level editor

Web level editor for Thrust (C64), live at <https://thrust.hayesmaker64.com>
(hosting: [`deploy/README.md`](../../deploy/README.md)).

**Using the editor: see the [user guide](docs/user-guide.md).** This README is
for working on the editor itself. Plan and status:
[`docs/level_editor_plan.md`](../../docs/level_editor_plan.md).

```
cd packages/level-editor
npm install
npm run dev       # editor + build API at http://localhost:5173
npm run serve     # or: production build served by server/index.ts at http://127.0.0.1:5180
npm test          # tests (KickAssembler ones need java and /opt/KickAss.jar; KICKASS=... overrides)
```

New games start from the **template**, `packages/thrusty-levels/examples/template.json`
(`GET /api/template`; `THRUST_TEMPLATE` overrides): the original six levels written
into the mod's `levels.asm` + `level_tables.asm`. Without it, new games start from
the mod's own level files. Remake it after changing the mod's level files:
`npm run mod-to-game -- --original ../thrusty-levels/examples/template.json thrust`
(without `--original`: a game file of the mod's own levels). A game is saved
as one JSON file (Game section: Save / Save as / Open / New from template;
in Chrome and Edge, Save writes back to the same file via the File System
Access API, elsewhere it downloads `<name>.json`). Edits also autosave in the
browser. **Build & play** (Ctrl+Enter) builds a temp copy
of the mod with KickAssembler and runs it in the embedded c64-ready emulator,
starting on the level you are editing (untick "start the game on this level"
for the normal game); "play full screen" for the whole screen. Keys in the game: Space start / shield, A S rotate,
Shift thrust, Return fire, F5/F7 pause/resume, Esc abort. The on-screen pad
(touch) and gamepads press the same keys (`src/editor/controls.ts`). For fun:
[how Claude beat mission 1](docs/autopilot-run.md) with an autopilot that
reads the C64's memory and presses those keys.

The editor never writes the mod. "Assembler files" offers the game as the two
level files (to drop into the mod and build by hand) and the terrain `.byte`
lines for copy and paste.

Game file: `{format: "thrust-level-editor/game", version: 1, name, levelsAsm,
tablesAsm, levels, level}`: the levels plus the level files they patch, so a
game builds even after the template changes.

To write a saved game into the mod: `npm run game-to-mod -- my-game.json`
writes its levels into the mod's `levels.asm` / `level_tables.asm` (the rest
of those files is kept), then `./packages/thrusty-levels/build.sh`.

`THRUST_MOD_SRC` points the server at another mod folder. Build server settings:
`KICKASS` (the jar), `KICKASS_JAVA` (the command that runs it, e.g. the sandbox
`deploy/kickass-sandbox.sh`), `BUILD_TIMEOUT_MS` (120000), `BUILD_MAX_QUEUE` (8),
`BUILDS_DIR`. Hosting: [`deploy/README.md`](../../deploy/README.md).

**Memory:** the Level section shows a rough meter per place the level data
lives. For thrusty-levels (which defines `LEVELS_AREA_START/END` in
`thrust.asm`): terrain + objects in `$1000-$1FFF` (4096 bytes) and restart
points in the main block; for the original layout one main-block meter
(~1240 bytes). Below 10% (or 64 bytes) free it turns amber with a "memory is
tight" banner by Build & play; over budget it turns red, the Checks list an
error, and the build fails with KickAssembler's message (the build server
also treats a failed `.assert` as an error).

## Build API (`server/`)

`api.ts` is a dependency-free Node handler (the Vite dev server and
`index.ts` both use it); `paths.ts` holds the folders.

| Route | |
|---|---|
| `GET /api/source` | the mod's two level files + a hash + the memory layout |
| `GET /api/template` | the game new games start from (404: none) |
| `POST /api/build` | `{levelsAsm, tablesAsm, startLevel?}` -> `{ok, errors, log, files, id}` |
| `GET /api/builds/<id>/<file>` | `thrust.prg`, `play.prg` (starts on `startLevel`), `.sym`, `.vs`, `kickass.log` |

Build files are served with CORS, so c64-ready elsewhere can load them:
`https://hayesmaker.github.io/c64-ready/?game=http://localhost:5173/api/builds/<id>/play.prg`
("Open in c64-ready" in the panel).

Controls: drag a point to move it (Shift: whole step per row, i.e. a pure
slope); click a wall line to add a point; drag objects (they snap to the
terrain, Alt: free) and restart crosses (the screen window follows);
right-click or Del deletes; arrows nudge; drag / wheel pans; Ctrl+wheel or
+/- zooms; F fits; 1-6 picks the level; Ctrl+Z / Ctrl+Shift+Z undo / redo.
Dashed segments are uneven slopes: they become staircases and cost more
table entries. Add objects from the palette in the Objects section; gravity
and colours are under "Gravity and colours"; the Checks section lists rule
violations (click one to select the object).

## Model (`src/model/`)

* `terrain.ts` - the game's wall decoder, and walls as points `{row, x}`:
  `encodeWall` (points -> A/B or C/D tables), `importWall` (tables -> points).
  `points[0]` is a fixed anchor at row 254 (end of the sky run). X is kept
  unwrapped so walls stay continuous across the 0/255 wrap.
* `asm.ts` - reads labelled `.byte` blocks from KickAssembler source and
  rewrites only the lines that changed.
* `objects.ts` - per-type snapping to the terrain, gun parameters and arcs.
* `validate.ts` - level checks and the memory budget.
* `level.ts` - `loadProject(levelsAsm, tablesAsm)` / `saveProject(project)`
  for `packages/thrusty-levels/src/levels.asm` + `level_tables.asm`.
  Walls that were not edited keep their original bytes (`Wall.raw`); call
  `touchWall()` after changing a wall's points.

## UI (`src/editor/`)

`store.ts` (state, undo, autosave), `view.ts` (canvas), `input.ts`
(mouse/keys), `ops.ts` (point edits with the format's constraints),
`panel.ts` (side panel), `export.ts`, `api.ts` (build API client),
`player.ts` (c64-ready emulator overlay, on-screen pad, gamepad polling),
`controls.ts` (pad / gamepad -> Thrust's keys).

Test fixture `test/fixtures/original_levels.json` is made from the original
build by `python3 tools/level2json.py` (run `./build.sh` first).
