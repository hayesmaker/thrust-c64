"""Render the Thrust levels as PNG maps from a PRG (default: the build output).

Usage: python3 tools/levelview.py [build/thrust.prg] [outdir]

Reads the level tables the same way the game does (pointer tables in the
relocated main block), so it works on modified builds as long as the table
addresses are found through the symbol file build/thrust.sym.

Map: one pixel row per world row (the game draws every other row), each world
X unit (4 C64 pixels) is 2 pixels wide. The world is 256 units wide and wraps.
Rock = outside the left/right walls. Objects are drawn as boxes using the
object width/height tables; restart points as white crosses.
"""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from render import png, PAL

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
prg = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'build/thrust.prg')
outdir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'docs/levels')
symfile = os.path.splitext(prg)[0] + '.sym'

d = open(prg, 'rb').read()
la = d[0] | d[1] << 8
mem = bytearray(65536)
mem[la:la + len(d) - 2] = d[2:]

# symbols (KickAssembler .sym: ".label name=$1234")
sym = {}
if os.path.exists(symfile):
    for ln in open(symfile):
        m = re.match(r'\s*\.label\s+(\w+)\s*=\s*\$([0-9a-fA-F]+)', ln)
        if m:
            sym[m.group(1)] = int(m.group(2), 16)
S = lambda n, default: sym.get(n, default)

# the main block is copied from $3000 up to $8280 at start-up
R = bytearray(65536)
R[0x8280:0x10000] = mem[0x3000:0x3000 + 0x10000 - 0x8280]
# $0801-$2FFF runs in place (thrusty-levels keeps level data at $1000)
R[0x0801:0x3000] = mem[0x0801:0x3000]


def rd(a):
    return R[a]


def ptr(lo, hi, i):
    return rd(lo + i) | rd(hi + i) << 8


def word(tab, i):
    return rd(tab + i * 2) | rd(tab + i * 2 + 1) << 8


def decode(cnt, inc, rows, start_x):
    """Model of terrain_accumulate_xpos_fn for the decoder that starts at
    index 1 (the one whose values end up in the wall arrays)."""
    x, c, i = start_x, 0xff, 1
    out = []
    ended = False
    for _ in range(rows):
        if c == 0 and not ended:
            i += 1
            c = rd(cnt + i)
            ended = c == 0xff          # final segment: wall stays put
        if not ended:
            x = (x + rd(inc + i)) & 0xff
        c = (c - 1) & 0xff
        out.append(x)
    return out


def total_rows(cnt):
    n, i = 0, 1
    while True:
        c = rd(cnt + i)
        n += c if c else 256
        if i > 1 and c == 0xff:
            return n
        i += 1
        if i > 200:
            return n


NLEV = 6
t_lc, t_lch = S('terrain_left_wall_counter_ptrs_LO', 0xa8fd), S('terrain_left_wall_counter_ptrs_HI', 0xa903)
t_li, t_lih = S('terrain_left_wall_increment_ptrs_LO', 0xa909), S('terrain_left_wall_increment_ptrs_HI', 0xa90f)
t_rc, t_rch = S('terrain_right_wall_counter_ptrs_LO', 0xa915), S('terrain_right_wall_counter_ptrs_HI', 0xa91b)
t_ri, t_rih = S('terrain_right_wall_increment_ptrs_LO', 0xa921), S('terrain_right_wall_increment_ptrs_HI', 0xa927)
o_x, o_y = S('level_obj_pos_X_lookup', 0xa95e), S('level_obj_pos_Y_lookup', 0xa96a)
o_ye, o_t = S('level_obj_pos_Y_EXT_lookup', 0xa976), S('level_obj_type_lookup', 0xa982)
w_tab, h_tab = S('obj_type_width', 0x84f1), S('obj_type_height', 0x84fa)
rs_sizes = S('level_reset_data_sizes', 0xa873)
rs_lo, rs_hi = S('level_reset_ptr_table_LO', 0xa8df), S('level_reset_ptr_table_HI', 0xa8e5)
col_tab = S('level_colour_terrain', 0xa92d)

OBJ_COL = {0: 2, 1: 2, 2: 2, 3: 2, 4: 7, 5: 5, 6: 14, 7: 4, 8: 4}
OBJ_NAME = ['gun up-right', 'gun down-right', 'gun up-left', 'gun down-left', 'fuel', 'pod stand',
            'generator', 'door switch R', 'door switch L']

os.makedirs(outdir, exist_ok=True)
summary = []
for lv in range(NLEV):
    lc, li = ptr(t_lc, t_lch, lv), ptr(t_li, t_lih, lv)
    rc, ri = ptr(t_rc, t_rch, lv), ptr(t_ri, t_rih, lv)
    rows = max(total_rows(lc), total_rows(rc)) + 16
    L = decode(lc, li, rows, 0x00)
    Rw = decode(rc, ri, rows, 0xff)
    top = 0x100                       # skip most of the empty sky
    H = rows - top
    W = 256 * 2
    rock = rd(col_tab + lv) or 9
    img = [[0] * W for _ in range(H)]
    for y in range(H):
        l, r = L[y + top], Rw[y + top]
        for x in range(256):
            solid = (x < l or x > r) if l < r else True
            if solid:
                img[y][2 * x] = img[y][2 * x + 1] = rock
    # doors (hard-coded in tick_door_logic), drawn closed in orange
    doors = {3: (0x269, [0xae] * 13), 4: (0x344, [0xa6] * 21),
             5: (0x370, [0xc0 + k for k in range(7)] + [0xc7 - k for k in range(8)])}
    if lv in doors:
        y0, xs = doors[lv]
        for k, dx in enumerate(xs):
            yy = y0 + k - top
            if 0 <= yy < H:
                for x in range(L[y0 + k], dx):
                    img[yy][2 * x] = img[yy][2 * x + 1] = 8
    objs = []
    px, py, pye, pt = word(o_x, lv), word(o_y, lv), word(o_ye, lv), word(o_t, lv)
    i = 0
    while rd(pt + i) != 0xff and i < 40:
        t = rd(pt + i)
        X, Y = rd(px + i), rd(pye + i) * 256 + rd(py + i)
        w, h = (rd(w_tab + t) if t < 9 else 4), (rd(h_tab + t) if t < 9 else 8)
        objs.append((i, OBJ_NAME[t] if t < 9 else 'type %d' % t, X, Y))
        for yy in range(Y - top, Y - top + h):
            for xx in range(X, X + w):
                if 0 <= yy < H:
                    img[yy][(2 * xx) % W] = img[yy][(2 * xx + 1) % W] = OBJ_COL.get(t, 1)
        i += 1
    n = rd(rs_sizes + lv)
    rp = ptr(rs_lo, rs_hi, lv)
    restarts = []
    for k in range(n):
        vals = [rd(rp + row * n + k) for row in range(6)]
        Y, X = vals[0] * 256 + vals[1], vals[5]
        restarts.append((X, Y))
        for dd in range(-3, 4):
            for (xx, yy) in ((X + dd, Y), (X, Y + dd)):
                if 0 <= yy - top < H:
                    img[yy - top][(2 * xx) % W] = 1
    path = os.path.join(outdir, 'level_%d.png' % lv)
    png(path, W, H, img)
    summary.append((lv, rows, objs, restarts))
    print('level %d: %d rows, %d objects, %d restart points -> %s' % (lv, rows, len(objs), len(restarts), path))

with open(os.path.join(outdir, 'levels.txt'), 'w') as f:
    for lv, rows, objs, restarts in summary:
        f.write('Level %d (%d rows; map starts at world row $100)\n' % (lv, rows))
        for (i, name, X, Y) in objs:
            f.write('  object %2d  %-15s X $%02x  Y $%03x\n' % (i, name, X, Y))
        for k, (X, Y) in enumerate(restarts):
            f.write('  restart %d  ship X $%02x  Y $%03x\n' % (k, X, Y))
        f.write('\n')
