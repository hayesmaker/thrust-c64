# thrusty-levels - modded Thrust levels

Development folder for new and modified levels. `src/*.asm` here started as
a copy of the generated `../src/*.asm` (snapshot of 2026-10-04) and is edited
by hand; `tools/regen.sh` never touches it.

```
./thrusty-levels/build.sh          # -> thrusty-levels/build/thrusty-levels.prg (+ .sym, .vs)
./thrusty-levels/build.sh run      # build and start in VICE
python3 tools/terrainview.py 0 thrusty-levels/build/thrusty-levels.prg thrusty-levels/build/level_0_terrain.png
python3 tools/levelview.py thrusty-levels/build/thrusty-levels.prg thrusty-levels/build/levels
```

The build script says whether the result is still identical to
`orig/thrust_unpacked.prg`. See `docs/level_format.md` for the level data
format and where new levels fit in memory.

Names and comments added to the main generator later will not appear here
automatically.

## examples/

* `levels_slope_test.asm` - `levels.asm` with level 0 replaced by the slope
  test level (+-2/+-3 slopes and staircases), the source of
  `build/thrust_testlevel.prg`. To use it:
  `cp thrusty-levels/examples/levels_slope_test.asm thrusty-levels/src/levels.asm`
