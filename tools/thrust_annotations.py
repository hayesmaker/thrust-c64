"""Annotations for the Thrust (C64) disassembly: memory layout, labels,
comments and data formats. All addresses are RUNTIME addresses unless noted."""

SHOW_ADDR = True      # append runtime address + bytes to every line

HEADER = """
THRUST (Commodore 64) - Firebird, 1986
Game by Jeremy C. Smith, music by Rob Hubbard.
Commented disassembly for KickAssembler 5.x

Build:   ./build.sh   (java -jar KickAss.jar src/thrust.asm -odir ../build)
Result:  byte-identical to the unpacked original (orig/thrust_unpacked.prg)

Files:   thrust.asm        this file: layout, code, tables
         levels.asm        terrain + object data       (see docs/level_format.md)
         level_tables.asm  restart points, gravity, pointers, colours
         music.asm         Rob Hubbard music driver + theme
         sprites.asm       sprite graphics

The PRG loads at $0801 and is started with SYS 27684 ($6C24). Most of the
program is then relocated: each section below is assembled at its LOAD address
but labelled with its RUNTIME address via .pseudopc.

   load $2000-$2FFF  -> $2000  music driver (runs in place)
   load $3000-$3002  -> $3000  JMP music_driver (runs in place)
   load $3003-$6C23  -> $8283  main game code + data (relocator copies $3000-$6CFF to $8280)
   load $6C24-$6C54  -> $6C24  entry point / relocator (runs in place)
   load $6C55-$7954  -> $4000  sprite graphics (VIC bank 1)
   init copies sub-blocks of the main code to $0100, $0400, $0880-$09BF, $0E00.

Every address in the comments ($xxxx) is the RUNTIME address - use it with the
VICE monitor (build/thrust.vs has all labels). Names and many comments of the
game logic come from the BBC Micro disassembly by Kieran HJ Connell; the C64
specific parts (VIC, sprites, raster interrupts, SID, keyboard) are new.
"""

PREAMBLE = """
// The relocator copies everything from music_stub_load ($3000) upwards to $8280
.label RELOC_OFFSET = $8280 - $3000
"""

RELOC_DELTA = 0x5280

POSTAMBLE = """
// ----------------------------------------------------------------------------
// Layout checks
// ----------------------------------------------------------------------------
.assert "relocator source is $3000", music_stub_load, $3000
.assert "SYS address needs 5 digits", entry >= 10000, true
.assert "music must end below $3000", music_stub_load <= $3000, true
.assert "main code must end below $C000", main3_load + RELOC_OFFSET + (relocator_load - main3_load) <= $c000, true
"""

BASIC_STUB = """
    .word basic_end                             // link to next BASIC line
    .word 1987                                  // line number
    .byte $9e, '('                              // SYS(
    .byte '0' + floor(entry / 10000)            // entry address as 5 decimal digits
    .byte '0' + mod(floor(entry / 1000), 10)
    .byte '0' + mod(floor(entry / 100), 10)
    .byte '0' + mod(floor(entry / 10), 10)
    .byte '0' + mod(entry, 10)
    .encoding "petscii_upper"
    .text ") KASPER"
    .byte $00                                   // end of line
basic_end:
    .word $0000                                 // end of program
"""

# (name, load_start, load_end_exclusive, runtime_start, note)
PIECES = [
    ('basic_stub', 0x0801, 0x0817, 0x0801, 'BASIC line: 1987 SYS(27684) KASPER\n'
     '"KASPER" is probably a cracker\'s tag - there is no crack intro in this version'),
    ('filler1', 0x0817, 0x2000, 0x0817, 'Unused filler ($FA) left by the cruncher'),
    ('music', 0x2000, 0x3000, 0x2000, 'Music / sound effects driver and data. Runs in place.'),
    ('music_stub', 0x3000, 0x3003, 0x3000, 'JMP to the music driver, called each frame via JSR $3000.\n'
     'These three bytes are also the first bytes copied by the relocator\n(their copy at $8280 is never used).'),
    ('main1', 0x3003, 0x6493, 0x8283, 'Main game code (relocated to $8283-$B712)'),
    ('raster_table', 0x6493, 0x6499, 0x0e00, 'Raster interrupt table - copied to $0E00 at init\n'
     '(the copy loop moves 12 bytes; the last 6 are the code that follows)'),
    ('main2', 0x6499, 0x6501, 0xb719, ''),
    ('init_low', 0x6501, 0x65f5, 0x0400, 'Second stage init - copied to $0400 and run from there'),
    ('hiscore_init', 0x65f5, 0x6675, 0x0100, 'High score table - copied to $0100 at init'),
    ('tab_0880', 0x6675, 0x6695, 0x0880, 'Table copied to $0880'),
    ('tab_08a0', 0x6695, 0x66b5, 0x08a0, 'Table copied to $08A0'),
    ('tab_0980', 0x66b5, 0x66d5, 0x0980, 'Table copied to $0980'),
    ('tab_09a0', 0x66d5, 0x66f5, 0x09a0, 'Table copied to $09A0'),
    ('tab_0900', 0x66f5, 0x676b, 0x0900, 'In-game messages copied to $0900\n'
     '(the copy loop moves 126 bytes; the last 8 belong to the text that follows)'),
    ('main3', 0x676b, 0x6c24, 0xb9eb, ''),
    ('relocator', 0x6c24, 0x6c55, 0x6c24, 'Program entry (SYS 27684): relocate main block and start'),
    ('gfx', 0x6c55, 0x7955, 0x4000, 'Sprite and character graphics, copied to $4000 (VIC bank 1)'),
    ('filler2', 0x7955, 0x7f17, 0x7955, 'Unused filler ($FA) left by the cruncher'),
]

# parts of the source written to separate include files: (start_rt, end_rt, file, description)
SPLITS = [
    (0x2000, 0x3000, 'music.asm', 'Rob Hubbard music driver and Thrust theme'),
    (0xa03c, 0xa352, 'levels.asm', 'Level terrain and object data (6 levels)'),
    (0xa873, 0xa99a, 'level_tables.asm', 'Per-level tables: restart points, gravity, pointers, colours'),
    (0x4000, 0x4d00, 'sprites.asm', 'Sprite graphics'),
]

RAW_PIECES = {'filler1': 'fill', 'filler2': 'fill', 'basic_stub': 'basic'}

# Alias views of load ranges (used by copy loops that read the relocated
# block before it is copied on): (name, load_start, load_end, delta)
VIEWS = [
    ('main', 0x3003, 0x6c24, 0x5280),
]

ENTRY_POINTS = [0x6c24, 0xb683, 0x0400, 0x8943, 0x3000]

NO_RETURN = set()

# self-modified JMP/JSR whose assembled target is meaningless
NO_TRACE = {0x83fb}

# immediate lo/hi pairs that are NOT addresses (by runtime address of the first load, or value)
NO_PAIR = set()

# runtime ranges that must never be treated as code
DATA_RANGES_RT = []

LABELS = {
    0x6c24: 'entry',
    0xb683: 'init',
    0x0400: 'init2',
    0x8943: 'irq_handler',
    0x3000: 'music_play',
    0x2000: 'music_driver',
}

COMMENTS = {}
BLOCK_COMMENTS = {}
FORMATS = {}
OPERAND = {}
TABLES = {}       # start: (end_exclusive, name)
# zero page temporaries named per code range: (start_rt, end_rt, {zp: name})
ZP_RANGE_NAMES = []
RAM_TABLES = {}   # RAM areas outside the image: start: (end_exclusive, name)

# names that must be emitted as constants even though the address is inside
# the program image (runtime buffers overlaying one-shot init code/data)
RAM_LABELS = {
    0x0400: 'terrain_left_wall',
}
ZP = {}
RAM_COMMENTS = {}  # comments for RAM / hardware labels
ZP_COMMENTS = {}
OPERAND_NAMES = {}
IMMEDIATES = {}
CONSTS = {}


# ---------------------------------------------------------------------------
# merge per-area annotation modules
import importlib, glob, os as _os
for _f in sorted(glob.glob(_os.path.join(_os.path.dirname(__file__), 'ann_*.py'))):
    _m = importlib.import_module(_os.path.basename(_f)[:-3])
    for _k in ('LABELS', 'COMMENTS', 'BLOCK_COMMENTS', 'FORMATS', 'OPERAND', 'TABLES', 'RAM_LABELS',
               'RAM_TABLES', 'RAM_COMMENTS', 'ZP', 'ZP_COMMENTS', 'OPERAND_NAMES', 'IMMEDIATES', 'CONSTS'):
        if hasattr(_m, _k):
            globals()[_k].update(getattr(_m, _k))
    ENTRY_POINTS += getattr(_m, 'ENTRY_POINTS', [])
    DATA_RANGES_RT += getattr(_m, 'DATA_RANGES_RT', [])
    ZP_RANGE_NAMES += getattr(_m, 'ZP_RANGE_NAMES', [])
