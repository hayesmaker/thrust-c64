# Thrust (C64) — commented disassembly for KickAssembler

Thrust, Firebird 1986. Game by Jeremy C. Smith, music by Rob Hubbard.

This folder holds a complete, re-assemblable disassembly of the C64 version.
`./build.sh` assembles it with KickAssembler and checks that the output is
**byte-identical** to the original (unpacked) program.

```
./build.sh          # assemble -> build/thrust.prg (+ VICE labels build/thrust.vs) and verify
./build.sh run      # same, then start it in x64sc with the labels loaded
```

`KICKASS=/path/to/KickAss.jar ./build.sh` overrides the default `/opt/KickAss.jar`.

## Files

| Path | Contents |
|------|----------|
| `src/thrust.asm` | Main source: memory layout, all code, tables |
| `src/levels.asm` | Terrain and object data for the 6 levels |
| `src/level_tables.asm` | Per-level tables: restart points, gravity, data pointers, colours |
| `src/music.asm` | Rob Hubbard's music driver and the Thrust theme |
| `src/sprites.asm` | Sprite graphics (shown as `#`/`.` pictures in the comments) |
| `orig/thrust.prg` | Original packed file from the disk image |
| `orig/thrust_unpacked.prg` | The same program after decrunching — the build target |
| `orig/thrustpic.prg` | Original Thrust loading screen (separate file, not disassembled) |
| `docs/level_format.md` | Level data format and how to change / add levels |
| `docs/memory_map.md` | Run-time memory map, free RAM |
| `docs/levels/` | Maps of all 6 levels rendered from the data (`tools/levelview.py`) |
| `tools/` | The scripts used to produce the disassembly (see below) |

## How the program is laid out

The disk file is crunched twice. Once unpacked it is a single PRG at
`$0801-$7F16`, started with `SYS 27684` (`$6C24`). At start-up most of it is
moved elsewhere, so the source assembles each section at its *load* address
but labels it with its *run-time* address using `.pseudopc`:

| Load | Run time | What                                                                                         |
|------|----------|----------------------------------------------------------------------------------------------|
| `$0801` | `$0801` | BASIC line `1987 SYS(27684) KASPER` ("KASPER" is the cracker's tag; there is no crack intro) |
| `$2000-$2FFF` | same | music driver + data                                                                          |
| `$3000-$3002` | same | `JMP music_driver`, called every frame                                                       |
| `$3003-$6C23` | `$8283-$BEA3` | main game code and data                                                                      |
| `$6C24-$6C54` | same | entry point / relocator                                                                      |
| `$6C55-$7954` | `$4000-$4CFF` | sprite graphics                                                                              |

Inside the main block, `init` copies a few more pieces to low memory:
init code to `$0400`, the high score table to `$0100`, the angle tables to
`$0880-$09BF`, messages to `$0900` and the raster table to `$0E00`.

The source is relocatable: pseudopc start addresses, copy loop pointers and
page counts and the BASIC `SYS` number are all computed from labels, so code
and data can be added or removed. `.assert`s at the end of `thrust.asm` check
the layout limits. (Tested by inserting code in several places: the game still
runs normally.)

## How the C64 version works (short tour)

* The game logic is a direct port of the BBC Micro original: same zero page
  variables (except `$00/$01`, moved to `$62/$63`), same physics, same level
  data. Names and many comments come from the BBC disassembly, matched
  instruction by instruction.
* The playfield is a multicolour bitmap at `$6000` (VIC bank 1). The terrain
  is drawn with EOR every other line, like on the BBC.
* The status bar is a text screen with its own character set; a chain of
  raster interrupts (`irq_handler`, table at `$0E00`) switches modes.
* Ship (sprite 7) and pod (sprite 6) are hardware sprites; objects, bullets
  and the tether line use a sprite multiplexer (`sprite_list_add`,
  `sprite_bands_build`). Collisions use the VIC collision registers.
* Two colour screens (`$5C00`, `$5400`) differ only in terrain colour; showing
  the second one gives the "invisible landscape".
* Timing comes from a CIA timer interrupt (`game_tick_timer`).
* Keyboard only: A/S rotate, SHIFT thrust, RETURN fire, SPACE shield/tractor,
  F5/F7 pause/resume, F1/F3 sound off/on, RUN/STOP quit.

## Tools (how the disassembly was made)

| Script | Purpose |
|--------|---------|
| `tools/unpack.py` | Runs the packed PRG through a 6502 emulator to get the unpacked image |
| `tools/emu.py`, `tools/coverage.py` | Small C64 emulator that plays the demo and logs which bytes are executed / read / written |
| `tools/disasm.py` | Generator: code/data separation (coverage + tracing), labels, comments, KickAss output |
| `tools/bbcmatch.py`, `tools/apply_bbc.py` | Align the code with the BBC Micro disassembly to carry over names and comments |
| `tools/thrust_annotations.py`, `tools/ann_*.py` | All manual labels, comments and data formats |
| `tools/regen.sh` | Regenerate `src/*.asm` from the above and verify |
| `tools/levelview.py` | Render level maps from a built PRG |

`src/*.asm` is generated by `tools/regen.sh`. While renaming and commenting in
bulk it is easiest to keep editing the annotation files and regenerating.
Once you want to edit the `.asm` by hand, stop using `regen.sh` (it would
overwrite your edits) — from then on the `.asm` files are the master copy.

## Credits

* BBC Micro disassembly by Kieran HJ Connell (with later documentation), used
  for names and comments of the shared game logic: [../thrust-disassembly](https://github.com/kieranhj/thrust-disassembly)
* Music driver names follow Anthony McSweeney's commented disassembly of Rob
  Hubbard's "Monty on the Run" driver.
