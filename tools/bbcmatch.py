"""Align the C64 disassembly against the commented BBC Micro Thrust source
(../thrust-disassembly/thrust.6502) to transfer routine / variable names.

Matching works on instruction tokens (mnemonic + addressing mode + zero-page
operand value), anchored on unique n-grams and extended greedily.
Writes tools/bbc_map.py with proposed labels and per-instruction operand names.
"""
import sys, os, re
from collections import defaultdict, Counter
sys.path.insert(0, os.path.dirname(__file__))
import disasm as D

BBC = os.path.join(D.ROOT, '..', 'thrust-disassembly', 'thrust.6502')

# ------------------------------------------------------------ parse BBC
syms = {}
ASCII_MAP = {'\u2192': '->', '\u2190': '<-', '\u2212': '-', '\u2013': '-', '\u2014': '-', '\u00d7': 'x',
             '\u2248': '~', '\u2265': '>=', '\u2264': '<=', '\u2019': "'", '\u2018': "'", '\u201c': '"',
             '\u201d': '"', '\u00b1': '+/-', '\u2011': '-', '\u2010': '-', '\u00a0': ' ', '\u2026': '...',
             '\u2260': '!=', '\u00b7': '.', '\u2022': '*', '\u2191': 'up', '\u2193': 'down', '\u00b0': ' deg',
             '\u03c0': 'pi', '\u00f7': '/', '\u03b8': 'theta', '\u2080': '0', '\u0394': 'delta', '\u221d': '~',
             '\u03b1': 'alpha', '\u21d2': '=>'}


def to_ascii(t):
    t = ''.join(ASCII_MAP.get(ch, ch) for ch in t)
    return ''.join(ch if ord(ch) < 128 else '?' for ch in t)


lines = [to_ascii(l) for l in open(BBC, encoding='utf-8', errors='replace').read().splitlines()]


def strip_comment(s):
    out, q = '', False
    for ch in s:
        if ch == '"':
            q = not q
        if not q and ch in ';\\':
            break
        out += ch
    return out


def ev(expr):
    e = expr.strip()
    e = re.sub(r'\$([0-9A-Fa-f]+)', lambda m: str(int(m.group(1), 16)), e)
    e = re.sub(r'&([0-9A-Fa-f]+)', lambda m: str(int(m.group(1), 16)), e)
    e = e.replace(' AND ', ' & ').replace(' OR ', ' | ').replace(' DIV ', ' // ').replace('<<', '<<')
    e = re.sub(r'\bLO\(([^)]*)\)', r'((\1)&255)', e)
    e = re.sub(r'\bHI\(([^)]*)\)', r'(((\1)>>8)&255)', e)
    return eval(e, {}, syms)


for _ in range(3):
    for ln in lines:
        s = strip_comment(ln).strip()
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$', s)
        if m:
            try:
                syms[m.group(1)] = ev(m.group(2))
            except Exception:
                pass

MN = set('adc and asl bcc bcs beq bit bmi bne bpl brk bvc bvs clc cld cli clv cmp cpx cpy dec dex dey eor inc inx iny jmp jsr lda ldx ldy lsr nop ora pha php pla plp rol ror rti rts sbc sec sed sei sta stx sty tax tay tsx txa txs tya'.split())
BR = set('bcc bcs beq bmi bne bpl bvc bvs'.split())

bbc = []          # dicts: line, labels, mn, mode, opnd, val
pending = []
block = []        # comment-only lines seen since the last statement
label_block = {}  # bbc label -> block comment text
label_count = Counter()


def comment_of(ln):
    c = ln[len(strip_comment(ln)):]
    return c.lstrip(';\\ ').rstrip()


for no, ln in enumerate(lines, 1):
    s = strip_comment(ln).strip()
    if not s:
        c = comment_of(ln).strip(' *')
        if ln.strip().startswith(('\\', ';')) and c and not set(c) <= set('*-= '):
            block.append(c)
        elif not ln.strip():
            pass
        continue
    s = s.strip('{} ').strip()
    if not s:
        continue
    m = re.match(r'^\.([A-Za-z_][A-Za-z0-9_]*)\s*(.*)$', s)
    if m:
        label_count[m.group(1)] += 1
        if block:
            label_block[m.group(1)] = '\n'.join(block)
        block = []
        pending.append(m.group(1))
        s = m.group(2).strip()
        if not s:
            continue
    parts = s.split(None, 1)
    mn = parts[0].lower()
    if mn not in MN:
        if mn.upper() in ('EQUB', 'EQUW', 'EQUS', 'SKIP') or '=' in s:
            if mn.upper() in ('EQUB', 'EQUW', 'EQUS', 'SKIP'):
                bbc.append(dict(line=no, labels=pending, mn='.data', mode='', opnd='', val=None, cmt=''))
                pending = []
                block = []
        continue
    op = parts[1].strip() if len(parts) > 1 else ''
    val = None
    if op == '' or op.upper() == 'A':
        mode = 'acc' if op.upper() == 'A' or mn in ('asl', 'lsr', 'rol', 'ror') else 'imp'
        op = ''
    elif mn in BR:
        mode = 'rel'
    elif op.startswith('#'):
        mode = 'imm'
    else:
        u = op.replace(' ', '')
        idx = ''
        if re.search(r'\),Y$', u, re.I):
            mode, base = 'izy', u[1:-3]
        elif re.search(r',X\)$', u, re.I):
            mode, base = 'izx', u[1:-3]
        elif u.startswith('(') and u.endswith(')'):
            mode, base = 'ind', u[1:-1]
        else:
            if re.search(r',X$', u, re.I):
                idx, base = 'x', u[:-2]
            elif re.search(r',Y$', u, re.I):
                idx, base = 'y', u[:-2]
            else:
                base = u
            try:
                val = ev(base)
            except Exception:
                val = None
            zp = val is not None and val < 256 and mn not in ('jmp', 'jsr')
            mode = {('', True): 'zp', ('', False): 'abs', ('x', True): 'zpx', ('x', False): 'abx',
                    ('y', True): 'zpy', ('y', False): 'aby'}[(idx, zp)]
            if mode == 'zpy' and mn not in ('ldx', 'stx'):
                mode = 'aby'
        if mode in ('izy', 'izx', 'ind'):
            try:
                val = ev(base)
            except Exception:
                val = None
        op_base = base
    bbc.append(dict(line=no, labels=pending, mn=mn, mode=mode, opnd=op, val=val, cmt=comment_of(ln)))
    pending = []
    block = []

# ------------------------------------------------------------ C64 sequence
c64 = []
for l in sorted(D.insn_at):
    mn, mode, n = D.insn_at[l]
    p = D.piece_of[l]
    r = p.rt(l)
    v = D.IMG[l + 1] if n == 2 else (D.IMG[l + 1] | D.IMG[l + 2] << 8 if n == 3 else None)
    c64.append(dict(rt=r, l=l, mn=mn, mode=mode, val=v))


def tok(e):
    t = e['mn'] + ':' + e['mode']
    if e['mode'] in ('zp', 'zpx', 'zpy', 'izy', 'izx') and e['val'] is not None:
        t += ':%02x' % e['val']
    return t


bt = [tok(e) for e in bbc]
ct = [tok(e) for e in c64]

K = 5
cgrams = defaultdict(list)
for j in range(len(ct) - K):
    cgrams[tuple(ct[j:j + K])].append(j)
bgrams = Counter(tuple(bt[i:i + K]) for i in range(len(bt) - K))

pairs = {}
for i in range(len(bt) - K):
    g = tuple(bt[i:i + K])
    if '.data:' in g:
        continue
    js = cgrams.get(g)
    if js and len(js) == 1 and bgrams[g] == 1:
        j = js[0]
        for k in range(K):
            pairs[i + k] = j + k


def loose(a, b):
    return a.split(':')[:2] == b.split(':')[:2]


def contiguous(j1, j2):
    """C64 instructions j1..j2 form straight-line code (no gaps)."""
    for j in range(j1, j2):
        a, b = c64[j], c64[j + 1]
        if b['rt'] - a['rt'] != D.MODES[a['mode']]:
            return False
    return True


# fill gaps between anchors lying on the same diagonal, extend run ends a bit
strict = sorted(pairs.items())
MAXGAP, MAXEXT = 40, 4
for (i1, j1), (i2, j2) in zip(strict, strict[1:]):
    if i2 - i1 == j2 - j1 and 1 < i2 - i1 <= MAXGAP and contiguous(j1, j2):
        gap = [(i1 + k, j1 + k) for k in range(1, i2 - i1)]
        if sum(1 for ii, jj in gap if not loose(bt[ii], ct[jj])) <= 2:
            for ii, jj in gap:
                pairs.setdefault(ii, jj)
for i, j in sorted(pairs.items()):
    for di in (1, -1):
        for k in range(1, MAXEXT + 1):
            ii, jj = i + di * k, j + di * k
            if not (0 <= ii < len(bt) and 0 <= jj < len(ct)) or ii in pairs:
                break
            if not loose(bt[ii], ct[jj]) or not contiguous(min(j, jj), max(j, jj)):
                break
            pairs[ii] = jj

print('BBC insns %d, C64 insns %d, matched %d' % (sum(1 for e in bbc if e['mn'] != '.data'), len(c64), len(pairs)))

# ------------------------------------------------------------ transfer
label_votes = defaultdict(Counter)    # c64 rt -> name votes
sym_votes = defaultdict(Counter)      # bbc symbol -> c64 value votes
opnd_names = {}                       # c64 rt -> bbc operand text (zp temps)
for i, j in pairs.items():
    b, c = bbc[i], c64[j]
    for lab in b['labels']:
        label_votes[c['rt']][lab] += 1
    if b['mode'] in ('abs', 'abx', 'aby', 'ind') and c['val'] is not None and c['mode'] == b['mode']:
        base = re.sub(r'\s', '', b['opnd'])
        base = re.sub(r'^\(|\)$|,[XYxy]$|,[XYxy]\)$|\),[XYxy]$', '', base)
        mm = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)(?:([+-])(\$?[0-9A-Fa-f]+))?$', base)
        if mm:
            off = 0
            if mm.group(3):
                off = int(mm.group(3)[1:], 16) if mm.group(3).startswith('$') else int(mm.group(3))
                off = -off if mm.group(2) == '-' else off
            sym_votes[mm.group(1)][(c['val'] - off) & 0xffff] += 1
    if b['mode'] in ('zp', 'zpx', 'zpy', 'izy', 'izx') and c['val'] == b['val']:
        opnd_names[c['rt']] = b['opnd']
    if b['mode'] == 'rel':
        sym_votes[b['opnd'].strip()][None] += 0

# branch targets: BBC labels resolved by branches
for i, j in pairs.items():
    b, c = bbc[i], c64[j]
    if b['mode'] == 'rel':
        o = c['val']
        tgt = (c['rt'] + 2 + (o - 256 if o > 127 else o)) & 0xffff
        sym_votes[b['opnd'].strip()][tgt] += 1
    if b['mn'] in ('jsr', 'jmp') and b['mode'] == 'abs':
        sym_votes[b['opnd'].strip()][c['val']] += 1

out = open(os.path.join(D.HERE, 'bbc_map.py'), 'w')
out.write('# Generated by bbcmatch.py - BBC names proposed for C64 addresses\n')
out.write('LABEL_VOTES = {\n')
for rt in sorted(label_votes):
    out.write('    0x%04x: %r,\n' % (rt, dict(label_votes[rt])))
out.write('}\nSYM_VOTES = {\n')
for s in sorted(sym_votes):
    v = {k: n for k, n in sym_votes[s].items() if k is not None}
    if v:
        out.write('    %r: {%s},\n' % (s, ', '.join('0x%04x: %d' % (k, n) for k, n in sorted(v.items()))))
out.write('}\nOPERAND_NAMES = {\n')
for rt in sorted(opnd_names):
    out.write('    0x%04x: %r,\n' % (rt, opnd_names[rt]))
out.write('}\n')
out.write('INLINE_COMMENTS = {\n')
def imm_differs(b, c):
    if b['mode'] != 'imm' or c['mode'] != 'imm':
        return False
    try:
        return (ev(b['opnd'][1:]) & 255) != c['val']
    except Exception:
        return True


for i, j in sorted(pairs.items(), key=lambda t: t[1]):
    if bbc[i]['cmt'] and not imm_differs(bbc[i], c64[j]):
        out.write('    0x%04x: %r,\n' % (c64[j]['rt'], bbc[i]['cmt']))
out.write('}\nLABEL_BLOCKS = {\n')
for rt in sorted(label_votes):
    for lab in label_votes[rt]:
        if lab in label_block:
            out.write('    0x%04x: %r,\n' % (rt, label_block[lab]))
            break
out.write('}\nLABEL_COUNT = %r\n' % dict((k, v) for k, v in label_count.items() if v > 1))
out.write('IMMEDIATES = {\n')
for i, j in sorted(pairs.items(), key=lambda t: t[1]):
    b, c = bbc[i], c64[j]
    if b['mode'] == 'imm' and c['mode'] == 'imm' and re.search(r'[A-Za-z_]{2,}', b['opnd'][1:]):
        e = b['opnd'][1:].strip()
        try:
            same = (ev(e) & 255) == c['val']
        except Exception:
            same = None
        out.write('    0x%04x: (%r, %r),\n' % (c['rt'], e, same))
out.write('}\n')
# coverage of BBC routines
cov = Counter()
tot = Counter()
cur = None
for i, b in enumerate(bbc):
    if b['labels'] and b['mn'] != '.data':
        cur = b['labels'][0]
    if b['mn'] == '.data':
        cur = None
        continue
    if cur:
        tot[cur] += 1
        cov[cur] += i in pairs
print('BBC labels with any match: %d / %d' % (sum(1 for k in tot if cov[k]), len(tot)))

# ---- zero page correspondence statistics
zpmap = defaultdict(Counter)
for i, j in pairs.items():
    b, c = bbc[i], c64[j]
    if b['mode'] in ('zp', 'zpx', 'zpy', 'izy', 'izx') and c['mode'] == b['mode'] and b['val'] is not None:
        zpmap[b['val']][c['val']] += 1
with open(os.path.join(D.HERE, 'bbc_map.py'), 'a') as f:
    f.write('ZP_MAP = {\n')
    for k in sorted(zpmap):
        f.write('    0x%02x: {%s},\n' % (k, ', '.join('0x%02x: %d' % (a, n) for a, n in zpmap[k].most_common())))
    f.write('}\n')
if __name__ == '__main__':
    for k in sorted(zpmap):
        top = zpmap[k].most_common()
        if top[0][0] != k or len(top) > 1:
            print('bbc $%02x -> %s' % (k, ' '.join('$%02x:%d' % t for t in top)))
