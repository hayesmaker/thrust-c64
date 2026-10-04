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
| `levels.asm` (terrain, objects) | `$1000-$1FFF` (`LEVELS_AREA_START/END`) | 4096 bytes (842 used) |
| `level_tables.asm` (restart points, pointers, colours, gravity) | main block, must end below `$C000` | 1058 bytes free |

Both limits are `.errorif` checks in `thrust.asm`, so an overflow stops the
build with a message such as `levels.asm is 46 bytes too big for the levels
area $1000-$1fff`. (KickAssembler's `.assert` only prints a warning and still
writes the PRG.) The level editor shows both areas and warns when either gets
tight.

## Title screen

The high score screen (shown while the title music plays) has a title line,
"SUPER THRUSTY MAKER", on text row 16 under the table, in the game's own font;
"Press SPACE BAR to start." moved down from row 16 to row 18. The title
screen code calls `write_title_screen_texts` (end of the main block, 80 bytes)
instead of `write_press_spacebar`; change the text in `msg_title` in
`thrust.asm`. Message positions are bitmap addresses: `text_pos(row, col)` =
`$6000 + row * 320 + col * 8`.

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
