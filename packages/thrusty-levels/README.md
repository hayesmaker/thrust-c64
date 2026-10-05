# thrusty-levels - modded Thrust levels

Development folder for new and modified levels. The easiest way to edit them
is the web level editor: see the
[user guide](../level-editor/docs/user-guide.md). `src/*.asm` here started as
a copy of the generated `../../src/*.asm` (snapshot of 2026-10-04) and is edited
by hand; `tools/regen.sh` never touches it.

```
./packages/thrusty-levels/build.sh          # -> packages/thrusty-levels/build/thrusty-levels.prg (+ .sym, .vs)
./packages/thrusty-levels/build.sh run      # build and start in VICE
python3 tools/terrainview.py 0 packages/thrusty-levels/build/thrusty-levels.prg packages/thrusty-levels/build/level_0_terrain.png
python3 tools/levelview.py packages/thrusty-levels/build/thrusty-levels.prg packages/thrusty-levels/build/levels
```

The build script says whether the result is still identical to
`orig/thrust_unpacked.prg` (repo root). See `docs/level_format.md` for the level data
format and where new levels fit in memory.

Names and comments added to the main generator later will not appear here
automatically.

## Memory layout (differs from the original)

`levels.asm` (terrain + object tables) is assembled at `$1000-$1FFF` instead
of inside the main block: that area is free at run time, is part of the load
image (it was cruncher filler) and is not moved by the relocator. All level
data is reached through the pointer tables, so nothing else changed.

| Data | Where | Room |
|------|-------|------|
| `levels.asm` (terrain, objects, door shapes) | `$1000-$1FFF` (`LEVELS_AREA_START/END`) | 4096 bytes (894 used) |
| `level_tables.asm` (restart points, pointers, colours, gravity, doors, rules) | main block, must end below `$C000` | 997 bytes free |

Both limits are `.errorif` checks in `thrust.asm`, so an overflow stops the
build with a message such as `levels.asm is 46 bytes too big for the levels
area $1000-$1fff`. (KickAssembler's `.assert` only prints a warning and still
writes the PRG.) The level editor shows both areas and warns when either gets
tight.

## Doors and rules

Doors and the reverse gravity / invisible landscape rules are data here, not
code. The original game had a routine per door level in `tick_door_logic`;
the mod has one routine that reads per-level tables, and the default tables
give the original game's doors and round sequence. The level editor edits all
of this (Door and Rules in its side panel).

**Doors** (`level_door_*` in `level_tables.asm`, shapes `level_N_door_x` in
`levels.asm`). Each level has at most one door. Shooting any door switch
(object 7 or 8) on the level sets the switch counter to `level_door_time`; it
counts down one per tick. The opening grows one step per tick up to
`level_door_max`, stays there, and follows the counter back down to 0 (closed).

| Table | Meaning |
|-------|---------|
| `level_door_rows` | number of door rows; 0 = no door |
| `level_door_top_LO/HI` | world Y of the first door row |
| `level_door_mode` | bit 7: right wall (else left); bit 6: reveal (else slide) |
| `level_door_max` | maximum opening |
| `level_door_open_x` | reveal mode: wall X of an opened row |
| `level_door_time` | switch counter start value (`$FF` in the original) |
| `level_door_shape_LO/HI` | pointers to `level_N_door_x`: the closed wall X of each row |

Each tick the door is visible, `tick_door_logic` writes each row's wall X into
the decoded wall (`terrain_left_wall` or `terrain_right_wall`):

* slide: closed X minus the opening (left wall) or plus it (right wall). The
  original levels 3 (straight) and 5 (diamond) work this way.
* reveal: the top <opening> rows are `level_door_open_x`, the rest closed X.
  The original level 4 works this way.

A level without a door keeps one placeholder byte in `level_N_door_x`. The
routine is checked against the original three routines in the 6502 emulator:
the only difference is that the level 4 door is now also drawn when its top
row is exactly at the top of the window, and no longer when its last row is
at window offset `$FD`. The original routines disagreed by one row there.

**Rules** (`level_rule_*`, `round_cycle_*`). A round is one pass through all
six levels. Round `n` uses entry `n` of `round_cycle_reverse` and
`round_cycle_invisible` (`$00` off, `$FF` on), wrapping after the last entry.
The default is the original sequence: normal, reverse, invisible, reverse +
invisible. Both tables must have the same length (an `.errorif` checks it).
Each level's `level_rule_reverse` / `level_rule_invisible` then changes the
round's flag: 0 follow the round, 1 always on, 2 always off, 3 the opposite.
`apply_level_rules` works this out at the start of every level, so the
"reverse gravity" / "invisible landscape" messages appear the first time a
flag comes on, whichever level that is.

## Title screen

Text rows of the high score screen in the mod:

| Row | Content |
|-----|---------|
| 0-1 | status bar |
| 4 | "Top Eight Thrusters" (or "Congratulations") |
| 6-13 | high score table, QR code on the left |
| 15 | game name |
| 16 | "BY" author |
| 18 | "Press SPACE BAR to start." (row 16 in the original) |

The high score screen (shown while the title music plays) has two title lines
under the table, in the game's own font: the game's name from the level editor
on text row 15 ("SUPER THRUSTY MAKER" by default) and "BY <author>" on row 16;
"Press SPACE BAR to start." moved down from row 16 to row 18. The title
screen code calls `write_title_screen_texts` (end of the main block, 72 bytes)
instead of `write_press_spacebar`. The texts are `msg_title_text` and
`msg_author_text` (ASCII bytes, at most 28 each; a single space for no author)
at the end of `level_tables.asm`, where the editor writes them. Their positions
(`title_pos`, `author_pos`: centred by the assembler) and the length checks
are in `thrust.asm`, next to `write_title_screen_texts`, so the layout can
change without touching saved games. The font has A-Z (shown in upper case),
0-9, space and `.`; any other character shows as `.`. Message positions are
bitmap addresses: `text_pos(row, col)` = `$6000 + row * 320 + col * 8`.

Text screens are hires down to raster line `$B8` (inside row 16) and
multicolour below it, for the landscape. Row 18 is below the switch, so
`write_title_screen_texts` also sets the colours of the "Press SPACE BAR"
cells (otherwise some of its pixels show the terrain colour) and blanks the
lines under the 5-line glyphs. Text placed on rows 17 and lower needs the
same treatment.

Left of the table (rows 6-13, columns 0-7) is a QR code linking to the GitHub
repo (`HTTPS://GITHUB.COM/HAYESMAKER/THRUST-C64`; upper case fits a smaller
code). It is drawn by `plot_qr_code` in `src/title_qr.asm`, which sits in the
unused tail of the music area (`$2CAD-$2DB9`, 269 bytes; runs in place), so
it takes nothing from the level areas. The title screen is a hires bitmap: a
QR module is 2 pixels x 2 lines, white on black. To change the link:
`python3 packages/thrusty-levels/tools/qr2asm.py URL` (needs the Python
`qrcode` package) regenerates `src/title_qr_data.asm`; URLs up to 47
characters in upper case (or 32 in mixed case) fit.

## examples/

* `levels_slope_test.asm` - `levels.asm` with level 0 replaced by the slope
  test level (+-2/+-3 slopes and staircases), the source of
  `build/thrust_testlevel.prg`. To use it:
  `cp packages/thrusty-levels/examples/levels_slope_test.asm packages/thrusty-levels/src/levels.asm`
