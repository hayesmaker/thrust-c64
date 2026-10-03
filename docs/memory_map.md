# Thrust (C64) run-time memory map

After `init` has run. Determined from the code and from emulator access logs
(`tools/coverage.py`), so "free" means "never read or written during play".

| Range | Use |
|-------|-----|
| `$0000-$00FF` | zero page: game variables (same layout as the BBC version, `$00/$01` moved to `$62/$63`), temporaries `$70-$8F`, music `$E0-$FA` |
| `$0100-$017F` | high score table (8 × 16 bytes) |
| `$0180-$018F` | score (3 bytes BCD) and work bytes; stack above |
| `$0314-$0317` | IRQ/BRK vectors → `irq_handler` |
| `$0400-$04FF` | `terrain_left_wall` (init code runs here first) |
| `$0500-$05FF` | `terrain_right_wall` |
| `$0600-$07BF` | particle tables (32 entries each) |
| `$07C0-$07DF` | sprite multiplexer sort order |
| `$07E0-$07EB` | `obj_tractor_counter` (fuel collection) |
| `$0880-$08BF`, `$0980-$09BF` | angle → vector tables |
| `$08C0-$08C1` | saved KERNAL IRQ vector |
| `$0900-$097D` | in-game messages |
| `$09F7-$0AFF` | terrain drawing state |
| `$0B00-$0BEF` | terrain column → bitmap offset / pixel tables |
| `$0C00-$0FFF` | sprite multiplexer lists and raster interrupt table (`$0E00`) |
| `$1000-$1FFF` | **free** |
| `$2000-$2CAC` | music driver and data (`$2CAD-$2FFF` unused) |
| `$3000-$3002` | `JMP music_driver` |
| `$3003-$3FFF` | **free** (only the start-up copy reads it) |
| `$4000-$4CBF` | sprites (pointers `$00-$32`) |
| `$4CC0-$52FF` | **free**, inside the VIC bank (room for ~25 more sprites) |
| `$5300-$53FF` | tether line sprites (generated, pointers `$4C-$4F`) |
| `$5400-$57FF` | screen matrix B (playfield colours, invisible terrain) + sprite pointers |
| `$5800-$5AFF` | status bar character set |
| `$5C00-$5FFF` | screen matrix A (status bar + playfield colours) + sprite pointers |
| `$6000-$7F3F` | multicolour bitmap (playfield) |
| `$8000-$80FF` | **keep free**: the terrain renderer writes past the end of the bitmap here |
| `$8100-$827F` | free |
| `$8280-$BEA3` | main game code and data (`$8280-$8282` unused copy of the music JMP) |
| `$BEA4-$BF7F` | unused (left over from the start-up copy) |
| `$C000-$CFFF` | **free** |
| `$D000-$DFFF` | I/O |
| `$E000-$FFFF` | KERNAL ROM (only its IRQ entry is used) |

Banking: `$01` = `$36` (BASIC ROM off, KERNAL and I/O on), VIC bank 1
(`$4000-$7FFF`).

## Raster interrupt chain

`raster_table` (`$0E00`) holds 3-byte entries `[raster line, handler,
next line or $FF]`. Fixed entries: top of frame (status bar, keyboard scan,
sound, music), status bar colour change, switch to bitmap mode at the start of
the playfield. The multiplexer appends one entry per sprite band (handler 1)
every frame.

## Timing

The CIA 1 timer A interrupt (`$276A` cycles, ~97.6 Hz on PAL) decrements
`game_tick_timer`; the main loop (`wait_game_tick`) waits until it is negative
and adds 3, so the game logic runs at a fixed ~32 Hz independent of the
screen. The raster IRQ increments `vsync_count` once per frame (50 Hz).
