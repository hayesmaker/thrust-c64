"""Dump all level data from a built PRG to JSON (fixtures for the level editor).

Usage: python3 tools/level2json.py [build/thrust.prg] [out.json]

Default output: packages/level-editor/test/fixtures/original_levels.json.
For each level: the raw terrain tables A-D, the decoded wall X for every row
(same decoder model as levelview.py / terrainview.py), objects, restart
points, gravity and colours. Addresses come from the .sym next to the PRG.
"""
import sys, os, re, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
prg = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'build/thrust.prg')
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    ROOT, 'packages/level-editor/test/fixtures/original_levels.json')
symfile = os.path.splitext(prg)[0] + '.sym'

d = open(prg, 'rb').read()
la = d[0] | d[1] << 8
mem = bytearray(65536)
mem[la:la + len(d) - 2] = d[2:]
sym = {}
for ln in open(symfile):
    m = re.match(r'\s*\.label\s+(\w+)\s*=\s*\$([0-9a-fA-F]+)', ln)
    if m:
        sym[m.group(1)] = int(m.group(2), 16)
# the main block is copied from $3000 up to $8280 at start-up
R = bytearray(65536)
R[0x8280:0x10000] = mem[0x3000:0x3000 + 0x10000 - 0x8280]
# $0801-$2FFF runs in place (thrusty-levels keeps level data at $1000)
R[0x0801:0x3000] = mem[0x0801:0x3000]
rd = lambda a: R[a]
ptr = lambda t, i: rd(sym[t + '_LO'] + i) | rd(sym[t + '_HI'] + i) << 8
word = lambda t, i: rd(sym[t] + i * 2) | rd(sym[t] + i * 2 + 1) << 8


def table_len(cnt):
    """Entries up to and including the $FF terminator (entry 0 and 1 included)."""
    i = 2
    while rd(cnt + i) != 0xff:
        i += 1
    return i + 1


def decode(cnt, inc, rows, start_x):
    x, c, i = start_x, 0xff, 1
    xs, ended = [], False
    for _ in range(rows):
        if c == 0 and not ended:
            i += 1
            c = rd(cnt + i)
            ended = c == 0xff
        if not ended:
            x = (x + rd(inc + i)) & 0xff
        c = (c - 1) & 0xff
        xs.append(x)
    return xs


def total_rows(cnt):
    n, i = 0, 1
    while True:
        c = rd(cnt + i)
        if i > 1 and c == 0xff:
            return n
        n += 255 if i == 1 else (c if c else 256)
        i += 1


levels = []
for lv in range(6):
    walls = {}
    for side, cn, inn, sx in (('left', 'terrain_left_wall_counter_ptrs', 'terrain_left_wall_increment_ptrs', 0),
                              ('right', 'terrain_right_wall_counter_ptrs', 'terrain_right_wall_increment_ptrs', 0xff)):
        c, i = ptr(cn, lv), ptr(inn, lv)
        n = table_len(c)
        walls[side] = dict(counts=[rd(c + k) for k in range(n)], steps=[rd(i + k) for k in range(n)],
                           start=sx, rows=total_rows(c))
    rows = max(walls['left']['rows'], walls['right']['rows']) + 16
    for side in walls:
        w = walls[side]
        w['xs'] = decode(ptr('terrain_%s_wall_counter_ptrs' % side, lv),
                         ptr('terrain_%s_wall_increment_ptrs' % side, lv), rows, w['start'])
    px, py, pye, pt, pg = (word(t, lv) for t in ('level_obj_pos_X_lookup', 'level_obj_pos_Y_lookup',
                                                  'level_obj_pos_Y_EXT_lookup', 'level_obj_type_lookup',
                                                  'level_gun_param_lookup'))
    objs, k = [], 0
    while rd(pt + k) != 0xff:
        objs.append(dict(type=rd(pt + k), x=rd(px + k), y=rd(pye + k) * 256 + rd(py + k), gun=rd(pg + k)))
        k += 1
    n = rd(sym['level_reset_data_sizes'] + lv)
    rp = ptr('level_reset_ptr_table', lv)
    restarts = []
    for k in range(n):
        v = [rd(rp + row * n + k) for row in range(6)]
        restarts.append(dict(shipY=v[0] * 256 + v[1], windowX=v[2], windowY=v[3] * 256 + v[4], shipX=v[5]))
    colours = {c: rd(sym['level_colour_' + c] + lv) for c in ('terrain', 'mc1', 'mc3', 'status', 'objects', 'shield')}
    levels.append(dict(level=lv, walls=walls, objects=objs, restarts=restarts,
                       gravity=rd(sym['level_gravity_FRAC_table'] + lv), colours=colours))

os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'w') as f:
    json.dump(dict(source=os.path.relpath(prg, ROOT), levels=levels), f, separators=(',', ':'))
print('wrote', out)
