# thrusty-levels - modded Thrust levels

Development folder for new and modified levels. `src/*.asm` here started as
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
| `level_tables.asm` (restart points, pointers, colours, gravity) | main block, must end below `$C000` | 1138 bytes free |

Both limits are `.errorif` checks in `thrust.asm`, so an overflow stops the
build with a message such as `levels.asm is 46 bytes too big for the levels
area $1000-$1fff`. (KickAssembler's `.assert` only prints a warning and still
writes the PRG.) The level editor shows both areas and warns when either gets
tight.

## examples/

* `levels_slope_test.asm` - `levels.asm` with level 0 replaced by the slope
  test level (+-2/+-3 slopes and staircases), the source of
  `build/thrust_testlevel.prg`. To use it:
  `cp packages/thrusty-levels/examples/levels_slope_test.asm packages/thrusty-levels/src/levels.asm`
