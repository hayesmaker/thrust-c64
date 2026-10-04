"""Render one level's terrain zoomed in, with each terrain table entry labelled
in decimal next to the stretch of wall it produces.

Usage: python3 tools/terrainview.py [level] [build/thrust.prg] [out.png] [zoom]

Default output: docs/levels/level_N_terrain.png. Needs Pillow.

Each run i of a wall is drawn in its own colour and labelled
"A[i]=rows B[i]=step" (C/D for the right wall); steps >= 128 are also shown
signed. Only the rows where the walls change are shown (plus some margin);
the full tables are listed in the header.
"""
import sys, os, re
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(__file__))
from render import PAL

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lv = int(sys.argv[1]) if len(sys.argv) > 1 else 0
prg = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'build/thrust.prg')
out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(ROOT, 'docs/levels/level_%d_terrain.png' % lv)
ZY = int(sys.argv[4]) if len(sys.argv) > 4 else 8   # pixels per world row
ZX = ZY * 2                                         # X unit = 4 C64 pixels, row = 2
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
rd = lambda a: R[a]
ptr = lambda t, i: rd(sym[t + '_LO'] + i) | rd(sym[t + '_HI'] + i) << 8
word = lambda t, i: rd(sym[t] + i * 2) | rd(sym[t] + i * 2 + 1) << 8


def decode(cnt, inc, start_x):
    """Same model as levelview.decode, but also returns the runs:
    (index, first row, last row, x before the run, x after each row)."""
    x, c, i = start_x, 0xff, 1
    xs, runs = [], [[1, 0, 0, start_x]]
    ended = False
    row = 0
    while not ended or row < runs[-1][1] + 64:
        if c == 0 and not ended:
            i += 1
            c = rd(cnt + i)
            ended = c == 0xff
            runs.append([i, row, row, x])
        if not ended:
            x = (x + rd(inc + i)) & 0xff
        c = (c - 1) & 0xff
        xs.append(x)
        runs[-1][2] = row
        row += 1
    return xs, runs


def table(addr, n):
    return [rd(addr + k) for k in range(n)]


lc, li = ptr('terrain_left_wall_counter_ptrs', lv), ptr('terrain_left_wall_increment_ptrs', lv)
rc, ri = ptr('terrain_right_wall_counter_ptrs', lv), ptr('terrain_right_wall_increment_ptrs', lv)
L, Lruns = decode(lc, li, 0x00)
Rw, Rruns = decode(rc, ri, 0xff)
rows = min(len(L), len(Rw))
L, Rw = L[:rows], Rw[:rows]

# crop: from a little above the first change to a little below the last one
changes = [r[1] for r in Lruns[2:] + Rruns[2:]]
y0 = max(0, min(changes) - 24)
y1 = min(rows, max(changes) + 12)
wall_x = [L[y] for y in range(y0, y1)] + [Rw[y] for y in range(y0, y1)]
x0 = max(0, min(x for x in wall_x if x) - 16)
x1 = min(256, max(x for x in wall_x if x < 255) + 17)

font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 15)
fontb = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf', 18)
LM, TM = 110, 0          # left ruler margin; header height filled in below
mapw, maph = (x1 - x0) * ZX, (y1 - y0) * ZY

# header text: the raw tables
names = [('A', lc, 'left wall: run lengths'), ('B', li, 'left wall: X step per row'),
         ('C', rc, 'right wall: run lengths'), ('D', ri, 'right wall: X step per row')]
nl, nr = Lruns[-1][0] + 1, Rruns[-1][0] + 1
hdr = ['Level %d terrain   (world rows %d-%d, X %d-%d; %d px per row, %d px per X unit)'
       % (lv, y0, y1 - 1, x0, x1 - 1, ZY, ZX)]
for nm, addr, desc in names:
    n = nl if nm in 'AB' else nr
    hdr.append('%s $%04x  %-26s %s' % (nm, addr, desc, ' '.join('%3d' % v for v in table(addr, n))))
hdr.append('Entry 0 is never used; entries 1-2 are the sky above the crop.  Label = index: rows x step (signed)')
TM = 16 + 22 * len(hdr) + 30

W, H = LM + mapw + 20, TM + maph + 20
img = Image.new('RGB', (W, H), (16, 16, 24))
dr = ImageDraw.Draw(img)
for k, t in enumerate(hdr):
    dr.text((12, 10 + 22 * k), t, font=fontb if k == 0 else font, fill=(230, 230, 230))

# map: rock in the level colour, sky black
rock = PAL[rd(sym['level_colour_terrain'] + lv) or 9]
sky = (0, 0, 0)
for y in range(y0, y1):
    l, r = L[y], Rw[y]
    for x in range(x0, x1):
        solid = (x < l or x > r) if l < r else True
        px, py = LM + (x - x0) * ZX, TM + (y - y0) * ZY
        dr.rectangle([px, py, px + ZX - 1, py + ZY - 1], fill=rock if solid else sky)

# objects
OBJ_COL = {0: 2, 1: 2, 2: 2, 3: 2, 4: 7, 5: 5, 6: 14, 7: 4, 8: 4}
OBJ_NAME = ['gun', 'gun', 'gun', 'gun', 'fuel', 'pod', 'generator', 'switch', 'switch']
px_, py_, pye, pt = (word(t, lv) for t in ('level_obj_pos_X_lookup', 'level_obj_pos_Y_lookup',
                                           'level_obj_pos_Y_EXT_lookup', 'level_obj_type_lookup'))
i = 0
while rd(pt + i) != 0xff and i < 40:
    t = rd(pt + i)
    X, Y = rd(px_ + i), rd(pye + i) * 256 + rd(py_ + i)
    w, h = rd(sym['obj_type_width'] + t), rd(sym['obj_type_height'] + t)
    if y0 <= Y < y1 and x0 <= X < x1:
        bx, by = LM + (X - x0) * ZX, TM + (Y - y0) * ZY
        dr.rectangle([bx, by, bx + w * ZX - 1, by + h * ZY - 1], fill=PAL[OBJ_COL.get(t, 1)])
        dr.text((bx + 3, by + 3), '%d %s' % (i, OBJ_NAME[t]), font=font, fill=(255, 255, 255),
                stroke_width=2, stroke_fill=(0, 0, 0))
    i += 1

# grid + rulers
for y in range(y0, y1):
    py = TM + (y - y0) * ZY
    if y % 8 == 0:
        dr.line([LM, py, LM + mapw, py], fill=(60, 60, 70))
        dr.text((6, py - 8), '%3d $%03x' % (y, y), font=font, fill=(170, 170, 170))
for x in range(x0, x1):
    if x % 8 == 0:
        px = LM + (x - x0) * ZX
        dr.line([px, TM, px, TM + maph], fill=(60, 60, 70))
        dr.text((px - 12, TM - 22), '%3d' % x, font=font, fill=(170, 170, 170))

# walls: each run in its own colour, label next to the run
RUNCOL = [(255, 230, 0), (0, 230, 255), (255, 90, 200), (120, 255, 90), (255, 150, 40), (180, 140, 255)]
placed = []


def place(bx, by, tw, th):
    """Move a label box down until it overlaps no earlier label."""
    while any(bx < a + c and a < bx + tw and by < b + e and b < by + th for a, b, c, e in placed):
        by += 4
    placed.append((bx, by, tw, th))
    return by


def edge(x, left):
    # screen X of the boundary between rock and sky
    return LM + (x - x0 + (0 if left else 1)) * ZX


for left, xs, runs, cn, sn, cnt, inc in ((True, L, Lruns, 'A', 'B', lc, li),
                                         (False, Rw, Rruns, 'C', 'D', rc, ri)):
    for k, (i, ra, rb, xstart) in enumerate(runs):
        if rb < y0 or i < 2 and ra < y0 and rb < y0:
            continue
        col = RUNCOL[k % len(RUNCOL)]
        # trace the boundary from the previous x through this run
        pts = []
        prev = xstart
        for y in range(max(ra, y0), min(rb + 1, y1)):
            if L[y] >= Rw[y] and L[y - 1] >= Rw[y - 1]:
                break                     # walls have met: cave closed
            ty = TM + (y - y0) * ZY
            pts += [(edge(prev, left), ty), (edge(xs[y], left), ty), (edge(xs[y], left), ty + ZY)]
            prev = xs[y]
        if pts:
            dr.line(pts, fill=col, width=3)
        else:
            pts = [(edge(xstart, left), TM + (max(ra, y0) - y0) * ZY)]
        n, s = rd(cnt + i), rd(inc + i)
        ended = n == 0xff and i > 2
        txt = '%s%d=%d %s%d=%d' % (cn, i, n, sn, i, s)
        if s >= 128:
            txt += ' (%d)' % (s - 256)
        if ended:
            txt += '  end'
        tb = dr.textbbox((0, 0), txt, font=font)
        tw, th = tb[2] - tb[0] + 8, tb[3] - tb[1] + 8
        ax, ay = pts[len(pts) // 2]
        # left wall labels go into the sky to the right, right wall ones to the left
        bx = ax + 30 if left else ax - 30 - tw
        bx = max(LM, min(bx, LM + mapw - tw))
        by = place(bx, max(TM, ay - th - 24), tw, th)
        dr.line([ax, ay, bx + (0 if left else tw), by + th // 2], fill=col, width=1)
        dr.rectangle([bx, by, bx + tw, by + th], fill=(0, 0, 0), outline=col)
        dr.text((bx + 4, by + 3 - tb[1]), txt, font=font, fill=col)

os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
img.save(out)
print('%s  (%dx%d)' % (out, W, H))
