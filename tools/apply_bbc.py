"""Turn bbc_map.py (alignment votes) into tools/names_auto.py:
labels, zero-page names, per-instruction operand names, comments, constants.
Manual names in thrust_annotations.py always override these."""
import sys, os, re
from collections import Counter
sys.path.insert(0, os.path.dirname(__file__))
import bbc_map as M
import bbcmatch as B      # parsed BBC source (syms, lines)
import disasm as D
from c64regs import HW

ZP_REMAP = {0x00: 0x62, 0x01: 0x63, 0x62: 0xfb, 0x63: 0xfc}
AUTO_RE = re.compile(r'^L[0-9A-F]{4}$')
IGNORE = {'LFFFF', 'IRQ1V', 'WRCHV', 'L0205', 'L020F', 'zp_base', 'IRQ1_RETURN_A'}

lines = B.lines


def defs_in(lo, hi):
    """Symbol definitions (name, value, comment) between BBC source lines."""
    out = []
    for no in range(lo, hi):
        ln = lines[no - 1]
        s = B.strip_comment(ln).strip()
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$', s)
        if m and m.group(1) in B.syms:
            out.append((m.group(1), B.syms[m.group(1)], B.comment_of(ln)))
    return out


# --- zero page names (BBC lines 111-441) ------------------------------------
zp_names = {}          # name -> c64 address
zp_primary = {}        # c64 address -> name
zp_comment = {}
for name, val, cmt in defs_in(111, 442):
    if val >= 0x100 or name in IGNORE:
        continue
    a = ZP_REMAP.get(val, val)
    zp_names[name] = a
    if a not in zp_primary and not (0x70 <= a <= 0x8f):
        zp_primary[a] = name
        zp_comment[a] = cmt
for a in range(0x70, 0x90):
    zp_primary[a] = 'zp_tmp_%02x' % a
    zp_names[zp_primary[a]] = a
    names = [n for n, v in zp_names.items() if v == a and not n.startswith('zp_tmp')]
    zp_comment[a] = 'temp, also: ' + ', '.join(names[:6]) + (' ...' if len(names) > 6 else '')

# --- constants (BBC lines 38-110) --------------------------------------------
consts = {n: v for n, v, c in defs_in(38, 111)}
const_cmt = {n: c for n, v, c in defs_in(38, 111)}

# --- labels -----------------------------------------------------------------
labels = {}            # c64 rt -> name
taken = set()
for rt, votes in sorted(M.LABEL_VOTES.items()):
    names = [n for n in votes if not AUTO_RE.match(n) and n not in IGNORE]
    if names:
        labels[rt] = names[0]
# symbol votes for symbols not placed by label alignment
placed = set(labels.values())
data_syms = {}
for s, votes in M.SYM_VOTES.items():
    if s in placed or AUTO_RE.match(s) or s in IGNORE or s in zp_names:
        continue
    mc = Counter(votes).most_common(2)
    a, n = mc[0]
    if len(mc) > 1 and mc[1][1] == n:
        continue                      # tie - ambiguous
    if a < 0x100 or a >= 0xd000 or a in HW:
        continue
    if a in labels:
        continue
    labels[a] = s

# C64 routines often start a few bytes before the aligned BBC label (an extra
# instruction at entry). If call sites agree on a target just before the
# label position, move the name to the real entry point.
pos = {n: a for a, n in labels.items()}
moved = {}
for s_, votes in M.SYM_VOTES.items():
    if s_ in pos:
        t, c = Counter(votes).most_common(1)[0]
        P = pos[s_]
        if 0 < P - t <= 10 and t not in labels:
            l = D.rt2load.get(t)
            if l is not None and D.kind[l] == D.CODE:
                del labels[P]
                labels[t] = s_
                moved[P] = t

# make names unique: BBC-duplicate names get their parent's name as prefix
order = sorted(labels)
dups = set(M.LABEL_COUNT)
cnt = Counter(labels.values())
parent = None
final = {}
for rt in order:
    n = labels[rt]
    if n in dups or cnt[n] > 1:
        n = '%s_%s' % (parent or 'L%04x' % rt, n)
    else:
        parent = n
    while n in final.values():
        n = n + '_'
    final[rt] = n

# --- operand names for zp temporaries --------------------------------------
opnames = {}
for rt, txt in M.OPERAND_NAMES.items():
    base = re.sub(r'[\s()]', '', txt)
    base = re.sub(r',[XYxy]$', '', base)
    base = re.sub(r',[XYxy]$', '', base)
    if re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', base) and base in zp_names:
        opnames[rt] = base

# propagate names of zp temporaries to nearby unmatched uses of the same address
uses = {}            # rt -> zp addr for every zp-mode instruction
for l, (mn, mode, n) in D.insn_at.items():
    if mode in ('zp', 'zpx', 'zpy', 'izx', 'izy'):
        uses[D.piece_of[l].rt(l)] = D.IMG[l + 1]
named = sorted((rt, uses.get(rt), nm) for rt, nm in opnames.items())
for rt, a in uses.items():
    if rt in opnames or not (0x70 <= a <= 0x8f):
        continue
    best = None
    for rt2, a2, nm in named:
        if a2 == a and abs(rt2 - rt) <= 48:
            if best is None or abs(rt2 - rt) < best[0]:
                best = (abs(rt2 - rt), nm)
    if best:
        opnames[rt] = best[1]
        continue
    # high byte of a nearby named pointer?
    for rt2, a2, nm in named:
        if a2 == a - 1 and abs(rt2 - rt) <= 16 and not nm.endswith('+1'):
            opnames[rt] = nm + '+1'
            break

# --- immediates ---------------------------------------------------------------
imms = {}
for rt, (expr, same) in M.IMMEDIATES.items():
    if same and re.match(r'^[A-Z][A-Z0-9_]*$', expr) and expr in consts:
        imms[rt] = expr

# --- comments -----------------------------------------------------------------
def clean(c):
    return c.replace('**', '').strip()


comments = {rt: clean(c) for rt, c in M.INLINE_COMMENTS.items()}
blocks = {}
for rt, txt in M.LABEL_BLOCKS.items():
    ls = [l for l in txt.splitlines() if not re.match(r'^(Function|Functions):', l.strip())
          and l.strip() not in ('{', '}', '\\\\ {', '\\\\ }')]
    ls = [re.sub(r'^Description:\s*', '', l) for l in ls]
    t = '\n'.join(ls).strip()
    if t:
        blocks[moved.get(rt, rt)] = t

with open(os.path.join(D.HERE, 'names_auto.py'), 'w') as f:
    f.write('# Generated by apply_bbc.py from the BBC Micro disassembly alignment.\n')
    f.write('# Do not edit - put overrides in thrust_annotations.py\n\n')
    f.write('LABELS = {\n')
    for rt in sorted(final):
        f.write('    0x%04x: %r,\n' % (rt, final[rt]))
    f.write('}\n\nZP = {\n')
    for a in sorted(zp_primary):
        f.write('    0x%02x: %r,\n' % (a, zp_primary[a]))
    f.write('}\n\nZP_ALIASES = {\n')
    for n in sorted(zp_names, key=lambda n: (zp_names[n], n)):
        f.write('    %r: 0x%02x,\n' % (n, zp_names[n]))
    f.write('}\n\nZP_COMMENTS = {\n')
    for a in sorted(zp_comment):
        if zp_comment[a]:
            f.write('    0x%02x: %r,\n' % (a, zp_comment[a]))
    f.write('}\n\nOPERAND_NAMES = {\n')
    for rt in sorted(opnames):
        f.write('    0x%04x: %r,\n' % (rt, opnames[rt]))
    f.write('}\n\nCONSTS = {\n')
    for n in consts:
        f.write('    %r: (0x%02x, %r),\n' % (n, consts[n], const_cmt[n]))
    f.write('}\n\nIMMEDIATES = {\n')
    for rt in sorted(imms):
        f.write('    0x%04x: %r,\n' % (rt, imms[rt]))
    f.write('}\n\nCOMMENTS = {\n')
    for rt in sorted(comments):
        f.write('    0x%04x: %r,\n' % (rt, comments[rt]))
    f.write('}\n\nBLOCKS = {\n')
    for rt in sorted(blocks):
        f.write('    0x%04x: %r,\n' % (rt, blocks[rt]))
    f.write('}\n')
print('labels %d, zp %d, opnames %d, imms %d, comments %d, blocks %d' % (
    len(final), len(zp_primary), len(opnames), len(imms), len(comments), len(blocks)))
