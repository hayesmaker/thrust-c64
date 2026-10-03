"""Thrust (C64) disassembler -> KickAssembler source generator.

Inputs:
  orig/thrust_unpacked.prg          unpacked program image ($0801-$7F16)
  tools/coverage/*.pkl              emulator coverage (executed PCs, data accesses)
  tools/thrust_annotations.py       labels, comments, data formats, overrides

The load image is split into PIECES. Each piece has a runtime delta
(runtime = load + delta) because the game relocates most of itself at start-up.
Each piece is emitted as its own `.pseudopc` block, so labels inside carry their
runtime address while the bytes stay at their load address in the PRG.

Usage: python3 tools/disasm.py [out.asm]
"""
import sys, os, glob, pickle, re
from collections import defaultdict
sys.path.insert(0, os.path.dirname(__file__))
from cpu6502 import OPS, MODES
import thrust_annotations as A

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

prg = open(os.path.join(ROOT, 'orig/thrust_unpacked.prg'), 'rb').read()
LOAD0 = prg[0] | prg[1] << 8
IMG = bytearray(65536)
IMG[LOAD0:LOAD0 + len(prg) - 2] = prg[2:]
LOAD_END = LOAD0 + len(prg) - 2      # exclusive


class Piece:
    def __init__(self, name, lstart, lend, rstart, note=''):
        self.name, self.lstart, self.lend, self.rstart, self.note = name, lstart, lend, rstart, note
        self.delta = rstart - lstart

    def rt(self, l):
        return l + self.delta

    def contains_rt(self, r):
        return self.lstart <= r - self.delta < self.lend

    def __repr__(self):
        return '%s[%04x-%04x @%04x]' % (self.name, self.lstart, self.lend, self.rstart)


PIECES = [Piece(*p) for p in A.PIECES]
PIECES.sort(key=lambda p: p.lstart)
# sanity: contiguous coverage of the image
pos = LOAD0
for p in PIECES:
    assert p.lstart == pos, ('gap/overlap at', hex(pos), p)
    pos = p.lend
assert pos == LOAD_END, hex(pos)

piece_of = [None] * 65536
for p in PIECES:
    for l in range(p.lstart, p.lend):
        piece_of[l] = p

# runtime address -> load address (innermost views only)
rt2load = {}
for p in PIECES:
    if p.name in A.RAW_PIECES:
        continue
    for l in range(p.lstart, p.lend):
        r = p.rt(l)
        if r in rt2load:
            raise SystemExit('runtime clash %04x: %04x and %04x' % (r, rt2load[r], l))
        rt2load[r] = l

# extra "views": runtime aliases of a load range used by copy loops etc.
# (name, lstart, lend, delta) -> addresses resolve to piece_label + offset
VIEWS = [(n, ls, le, d) for (n, ls, le, d) in A.VIEWS]


def view_expr(v):
    """Express an address in an alias view as load-label arithmetic."""
    for (n, ls, le, d) in VIEWS:
        l = v - d
        if ls <= l < le:
            return n, l
    return None


# ---------------------------------------------------------------- coverage
exec_rt = {}
rd_log = defaultdict(set)
wr_log = defaultdict(set)
ind_jumps = defaultdict(set)
for f in sorted(glob.glob(os.path.join(HERE, 'coverage', '*.pkl'))):
    c = pickle.load(open(f, 'rb'))
    for pc, b in c['exec'].items():
        exec_rt[pc] = b
    for k, v in c['rd'].items():
        rd_log[k] |= v
    for k, v in c['wr'].items():
        wr_log[k] |= v
    for k, v in c['ind'].items():
        ind_jumps[k] |= v

# --------------------------------------------------------------- classify
CODE, OPER, DATA = 1, 2, 3
kind = [0] * 65536          # per load address
insn_at = {}                 # load -> (mn, mode, size)
problems = []


def try_insn(l):
    op = IMG[l]
    if op not in OPS:
        return None
    mn, mode = OPS[op]
    n = MODES[mode]
    p = piece_of[l]
    if p is None or l + n > p.lend:
        return None
    return mn, mode, n


def mark_code(l, why):
    """Mark instruction at load address l; return (mn, mode, n) or None."""
    if kind[l] == CODE:
        return insn_at[l]
    if kind[l] in (OPER, DATA):
        problems.append('%s: %04x (rt %04x) already %s' % (why, l, piece_of[l].rt(l), kind[l]))
        return None
    t = try_insn(l)
    if t is None:
        problems.append('%s: bad opcode at %04x (rt %04x)' % (why, l, piece_of[l].rt(l)))
        return None
    mn, mode, n = t
    for i in range(1, n):
        if kind[l + i] != 0:
            problems.append('%s: operand overlap at %04x (rt %04x)' % (why, l, piece_of[l].rt(l)))
            return None
    kind[l] = CODE
    for i in range(1, n):
        kind[l + i] = OPER
    insn_at[l] = t
    return t


def target(l, mode):
    p = piece_of[l]
    r = p.rt(l)
    if mode == 'rel':
        o = IMG[l + 1]
        return (r + 2 + (o - 256 if o > 127 else o)) & 0xffff
    return IMG[l + 1] | IMG[l + 2] << 8


not_code = set()
for (a, b) in A.DATA_RANGES_RT:
    for r in range(a, b):
        if r in rt2load:
            not_code.add(rt2load[r])


def trace(r, why):
    work = [r]
    while work:
        r = work.pop()
        while True:
            l = rt2load.get(r)
            if l is None or l in not_code:
                break
            if kind[l] == CODE:
                break
            t = mark_code(l, why + ' %04x' % r)
            if t is None:
                break
            mn, mode, n = t
            if r in A.NO_TRACE:
                if mn in ('jmp', 'rts', 'rti'):
                    break
                r += n
                continue
            if mode == 'rel':
                work.append(target(l, mode))
            if mn == 'jsr':
                tg = target(l, mode)
                work.append(tg)
                if tg in A.NO_RETURN:
                    break
            if mn == 'jmp':
                if mode == 'abs':
                    work.append(target(l, mode))
                break
            if mn in ('rts', 'rti', 'brk'):
                break
            r += n


# 1. dynamic: executed instructions whose opcode byte matches the image
for pc in sorted(exec_rt):
    l = rt2load.get(pc)
    if l is not None and IMG[l] == exec_rt[pc][0]:
        mark_code(l, 'exec')
for pc, tgts in ind_jumps.items():
    for t in tgts:
        trace(t, 'ind')
# 2. static: entry points from annotations + everything reachable from executed code
for e in A.ENTRY_POINTS:
    trace(e, 'entry')
for l in list(insn_at):
    mn, mode, n = insn_at[l]
    r = piece_of[l].rt(l)
    if (mode == 'rel' or (mn in ('jsr', 'jmp') and mode == 'abs')) and r not in A.NO_TRACE:
        trace(target(l, mode), 'from %04x' % r)
    if mn not in ('rts', 'rti', 'jmp', 'brk') and not (mn == 'jsr' and target(l, mode) in A.NO_RETURN):
        trace(r + n, 'fall %04x' % r)

# --------------------------------------------------------------- labels
try:
    import names_auto as N
except ImportError:
    N = None
from c64regs import HW

labels = {}            # runtime addr -> name (in-image, innermost view)
consts = {}            # addr -> name (outside image, or RAM overrides)
zp_names = {}          # zp addr -> primary name
zp_alias = {}          # alias name -> zp addr
used_aliases = set()
const_defs = {}        # .const NAME -> (value, comment)
used_consts = set()


def _add_label(a, n, manual):
    if a < 0x100:
        zp_names[a] = n
        zp_alias[n] = a
        return
    if a in rt2load and (manual or a not in A.RAM_LABELS):
        labels[a] = n
    else:
        consts[a] = n


if N:
    for a, n in N.ZP.items():
        zp_names[a] = n
    zp_alias.update(N.ZP_ALIASES)
    for a, n in N.LABELS.items():
        _add_label(a, n, False)
    for n, (v, c) in N.CONSTS.items():
        const_defs[n] = (v, c)
for a, n in HW.items():
    consts.setdefault(a, n)
manual_names = set(A.LABELS.values()) | set(A.RAM_LABELS.values())
# drop auto names that clash with manual ones
for d in (labels, consts):
    for a in list(d):
        if d[a] in manual_names and A.LABELS.get(a) != d[a] and A.RAM_LABELS.get(a) != d[a]:
            del d[a]
for n in list(zp_alias):
    if n in manual_names:
        del zp_alias[n]
for a, n in zp_names.items():
    zp_alias[n] = a
for a, n in A.LABELS.items():
    if a in consts and a not in A.RAM_LABELS:
        del consts[a]
    _add_label(a, n, True)
for a, n in A.RAM_LABELS.items():
    consts[a] = n
for a, n in A.ZP.items():
    zp_names[a] = n
    zp_alias[n] = a
names = list(labels.values()) + list(consts.values())
dup = [n for n in set(names) if names.count(n) > 1]
assert not dup, 'duplicate label names: %s' % dup

# tables: references inside [start, end) are written as name+offset
TABLES = sorted((a, e, n) for a, (e, n) in A.TABLES.items())
for (ts, te, tn) in TABLES:
    labels[ts] = tn
    for a in range(ts + 1, te):
        labels.pop(a, None)

COMMENTS = dict(N.COMMENTS) if N else {}
COMMENTS.update(A.COMMENTS)
BLOCKS = dict(N.BLOCKS) if N else {}
BLOCKS.update(A.BLOCK_COMMENTS)
OPNAMES = dict(N.OPERAND_NAMES) if N else {}
OPNAMES.update(A.OPERAND_NAMES)
IMMS = dict(N.IMMEDIATES) if N else {}
IMMS.update(A.IMMEDIATES)
const_defs.update(A.CONSTS)


def insn_start(l):
    """Load address of the instruction/data item containing l."""
    while kind[l] == OPER:
        l -= 1
    return l


def ref(v, data=False):
    """Symbolic text for address v (None if it should stay numeric)."""
    if v in A.RAM_LABELS and data:
        return A.RAM_LABELS[v]
    if v in labels:
        l = rt2load[v]
        if kind[l] != OPER:
            return labels[v]
    if v in consts:
        return consts[v]
    for (ts, te, tn) in TABLES:
        if ts < v < te:
            return '%s+%d' % (tn, v - ts)
    l = rt2load.get(v)
    if l is not None:
        s = insn_start(l)
        if s != l:
            if v in labels:
                return labels[v]          # emitted as .label name = *+k
            base = piece_of[s].rt(s)
            return '%s+%d' % (ref(base), v - base)
        nm = ('L' if kind[l] == CODE else 'D') + '%04x' % v
        labels[v] = nm
        return nm
    if l is None:
        for (rs, (re_, rn)) in sorted(A.RAM_TABLES.items()):
            if rs <= v < re_:
                used_ram_tables.add(rs)
                return rn if v == rs else '%s+$%02x' % (rn, v - rs)
    ve = view_expr(v)
    if ve:
        n, lo = ve
        p = piece_of[lo]
        off = lo - p.lstart
        return '%s_load%s+RELOC_OFFSET' % (p.name, '+$%x' % off if off else '')
    return None


def zpref(r, v):
    """Name for a zero-page operand of the instruction at runtime r."""
    if r in OPNAMES:
        nm = OPNAMES[r]
        base, plus = (nm[:-2], 1) if nm.endswith('+1') else (nm, 0)
        if zp_alias.get(base) == v - plus:
            used_aliases.add(base)
            return nm
    for (rs, re_, names) in A.ZP_RANGE_NAMES:
        if rs <= r < re_:
            for k in (0, 1):
                if v - k in names:
                    nm = names[v - k]
                    assert zp_alias.setdefault(nm, v - k) == v - k, 'zp name clash: %s' % nm
                    used_aliases.add(nm)
                    return nm + ('+1' if k else '')
    if v in zp_names:
        used_aliases.add(zp_names[v])
        return zp_names[v]
    if v - 1 in zp_names:
        used_aliases.add(zp_names[v - 1])
        return zp_names[v - 1] + '+1'
    return None


def hexv(v, w):
    return '$%0*x' % (w, v)


# lo/hi immediate pairs: lda #<x ... lda #>x feeding zp ptr / ptr+1 or two abs
imm_pairs = {}         # runtime addr of imm insn -> '<expr' / '>expr'


def find_imm_pairs():
    seq = sorted(insn_at)
    for k, l in enumerate(seq):
        mn, mode, n = insn_at[l]
        if mode != 'imm' or mn not in ('lda', 'ldx', 'ldy'):
            continue
        reg = mn[2]
        # next instruction stores this register
        if k + 1 >= len(seq):
            continue
        l2 = seq[k + 1]
        mn2, mode2, n2 = insn_at[l2]
        if mn2 != 'st' + reg or mode2 not in ('zp', 'abs'):
            continue
        dst = IMG[l2 + 1] | (IMG[l2 + 2] << 8 if n2 == 3 else 0)
        # look ahead a few instructions for imm load + store to dst+1
        for j in range(k + 2, min(k + 8, len(seq) - 1)):
            l3 = seq[j]
            mn3, mode3, n3 = insn_at[l3]
            if mode3 == 'imm' and mn3 in ('lda', 'ldx', 'ldy'):
                l4 = seq[j + 1]
                mn4, mode4, n4 = insn_at[l4]
                if mn4 == 'st' + mn3[2] and mode4 == mode2:
                    d2 = IMG[l4 + 1] | (IMG[l4 + 2] << 8 if n4 == 3 else 0)
                    if d2 == dst + 1:
                        v = IMG[l + 1] | IMG[l3 + 1] << 8
                        name = None
                        if 0xd000 <= dst < 0xe000:
                            break
                        if v in A.NO_PAIR or piece_of[l].rt(l) in A.NO_PAIR:
                            break
                        if (v in labels and not re.match(r'^[LD][0-9a-f]{4}$', labels[v])) or \
                                (v in consts and v not in HW):
                            name = ref(v)
                        elif dst < 0x100 and v >= 0x200 and (v in rt2load or view_expr(v)):
                            name = ref(v)
                        if name:
                            if re.search(r'[-+*/]', name):
                                name = '(%s)' % name
                            imm_pairs[piece_of[l].rt(l)] = '<' + name
                            imm_pairs[piece_of[l3].rt(l3)] = '>' + name
                        break
            if mn3 in ('jsr', 'jmp', 'rts', 'rti') or insn_at[l3][1] == 'rel':
                break


# ----------------------------------------------------------------- output
def fmt_operand(l, mn, mode, n):
    r = piece_of[l].rt(l)
    if r in A.OPERAND:
        return A.OPERAND[r]
    if mode in ('imp', 'acc'):
        return ''
    if mode == 'imm':
        if r in imm_pairs:
            return '#' + imm_pairs[r]
        if r in IMMS:
            nm = IMMS[r]
            if nm in const_defs and (const_defs[nm][0] & 255) == IMG[l + 1]:
                used_consts.add(nm)
                return '#' + nm
        return '#' + hexv(IMG[l + 1], 2)
    if mode == 'rel':
        return ref(target(l, mode)) or hexv(target(l, mode), 4)
    v = IMG[l + 1] if n == 2 else IMG[l + 1] | IMG[l + 2] << 8
    data = mn not in ('jmp', 'jsr')
    if n == 2 or v < 0x100:
        s = zpref(r, v)
    else:
        s = ref(v, data)
    if s is None:
        s = hexv(v, 2 if n == 2 else 4)
    suffix = {'zpx': ',x', 'abx': ',x', 'zpy': ',y', 'aby': ',y'}.get(mode, '')
    if mode == 'izx': return '(%s,x)' % s
    if mode == 'izy': return '(%s),y' % s
    if mode == 'ind': return '(%s)' % s
    return s + suffix


def needs_abs(l, mode, n):
    if n != 3 or mode in ('ind',):
        return False
    v = IMG[l + 1] | IMG[l + 2] << 8
    return v < 0x100 and IMG[l] != 0x20 and IMG[l] != 0x4c


def data_lines(lstart, lend):
    """Format a run of data bytes, 16 per line."""
    out = []
    l = lstart
    while l < lend:
        e = min(lend, l + 16)
        out.append((l, '.byte ' + ','.join('$%02x' % b for b in IMG[l:e]), ''))
        l = e
    return out


COMMENT_COL = 48


def line(text, r=None, c=''):
    if A.SHOW_ADDR and r is not None:
        c = ('$%04x  ' % r) + (c or '')
    if c:
        if len(text) >= COMMENT_COL:
            return '%s  // %s' % (text, c)
        return '%-*s// %s' % (COMMENT_COL, text, c)
    return text


def emit(path):
    derived = []
    o = []
    cur = [o]
    files = {}
    split_start = {a: (e, f, d) for (a, e, f, d) in A.SPLITS}
    split_end = None

    def w(x):
        cur[0].append(x)
    w('// ' + '=' * 76)
    for ln in A.HEADER.strip('\n').splitlines():
        w('// ' + ln if ln else '//')
    w('// ' + '=' * 76)
    w('')
    for ln in A.PREAMBLE.strip('\n').splitlines():
        w(ln)
    w('')
    # constants
    if used_consts:
        w('// ' + '-' * 76)
        w('// Constants')
        w('// ' + '-' * 76)
        for n in sorted(used_consts, key=lambda n: (const_defs[n][0], n)):
            v, c = const_defs[n]
            w(line('.const %-30s = $%02x' % (n, v), None, c))
        w('')
    w('// ' + '-' * 76)
    w('// Zero page')
    w('// ' + '-' * 76)
    zpc = dict(N.ZP_COMMENTS) if N else {}
    zpc.update(A.ZP_COMMENTS)
    for n in sorted(used_aliases, key=lambda n: (zp_alias[n], zp_names.get(zp_alias[n]) != n, n)):
        a = zp_alias[n]
        c = zpc.get(a, '') if zp_names.get(a) == n else ''
        w(line('.label %-30s = $%02x' % (n, a), None, c))
    w('')
    w('// ' + '-' * 76)
    w('// RAM work areas, hardware registers and KERNAL (outside the program image)')
    w('// ' + '-' * 76)
    for rs in sorted(A.RAM_TABLES):
        if rs in used_ram_tables and A.RAM_TABLES[rs][1] not in consts.values():
            consts[rs] = A.RAM_TABLES[rs][1]
    for a in sorted(consts):
        if consts[a] in used_names_out or a in A.RAM_LABELS:
            val = '$%04x' % a
            ve = view_expr(a) if a not in rt2load else None
            if ve:
                p_ = piece_of[ve[1]]
                off = ve[1] - p_.lstart
                val = '%s_load%s + RELOC_OFFSET' % (p_.name, ' + $%x' % off if off else '')
                derived.append(line('.label %-30s = %s' % (consts[a], val), None,
                                    'copy source of the block at $%04x' % rt2load.get(a, a)))
                continue
            w(line('.label %-30s = %s' % (consts[a], val), None, A.RAM_COMMENTS.get(a, '')))
    w('')
    w('* = $%04x "Thrust"' % LOAD0)
    for p in PIECES:
        w('')
        w('// ' + '=' * 76)
        w('// %s  (load $%04x-$%04x, runtime $%04x-$%04x)' % (p.name, p.lstart, p.lend - 1, p.rt(p.lstart), p.rt(p.lend - 1)))
        if p.note:
            for ln in p.note.strip('\n').splitlines():
                w('// ' + ln)
        w('// ' + '=' * 76)
        w('%s_load:' % p.name)
        if p.delta == A.RELOC_DELTA:
            w('.pseudopc %s_load + RELOC_OFFSET {' % p.name)
        elif p.delta:
            w('.pseudopc $%04x {' % p.rstart)
        if p.name in A.RAW_PIECES:
            if A.RAW_PIECES[p.name] == 'fill':
                w('    .fill $%04x, $%02x' % (p.lend - p.lstart, IMG[p.lstart]))
            elif A.RAW_PIECES[p.name] == 'fill_to':
                w('    .fill $%04x - *, $%02x                       // pad up to $%04x' % (p.lend, IMG[p.lstart], p.lend))
            elif A.RAW_PIECES[p.name] == 'basic':
                for ln in A.BASIC_STUB.strip('\n').splitlines():
                    w(ln)
            if p.delta:
                w('}')
            continue
        l = p.lstart
        while l < p.lend:
            r = p.rt(l)
            if split_end is not None and r >= split_end:
                cur[0] = o
                split_end = None
            if r in split_start:
                e_, f_, d_ = split_start[r]
                o.append('')
                o.append('    #import "%s"' % f_)
                files[f_] = [ '// ' + '=' * 76, '// %s - %s' % (f_, d_),
                              '// Included from thrust.asm. Runtime addresses $%04x-$%04x' % (r, e_ - 1),
                              '// ' + '=' * 76]
                cur[0] = files[f_]
                split_end = e_
                w('')
                w('// ' + '-' * 76)
                for ln in BLOCKS[r].strip('\n').splitlines():
                    w('// ' + ln if ln.strip() else '//')
                w('// ' + '-' * 76)
            if r in labels:
                w('%s:' % labels[r])
            if kind[l] == CODE:
                mn, mode, n = insn_at[l]
                for k in range(1, n):
                    if r + k in labels:
                        w('    .label %s = *+%d' % (labels[r + k], k))
                opnd = fmt_operand(l, mn, mode, n)
                m = mn + ('.a' if needs_abs(l, mode, n) else '')
                text = '    %s %s' % (m, opnd) if opnd else '    %s' % m
                w(line(text, r, COMMENTS.get(r, '')))
                l += n
            else:
                e = l + 1
                while e < p.lend and kind[e] != CODE and p.rt(e) not in labels and p.rt(e) not in BLOCKS \
                        and p.rt(e) not in A.FORMATS and p.rt(e) not in split_start and p.rt(e) not in split_ends:
                    e += 1
                fm = A.FORMATS.get(r)
                for (dl, text, cm) in format_data(l, e, fm):
                    rr = p.rt(dl)
                    if text.startswith('//'):
                        w(text)
                        continue
                    w(line('    ' + text, rr, COMMENTS.get(rr, cm)))
                l = e
        if split_end is not None and p.rt(p.lend) >= split_end:
            cur[0] = o
            split_end = None
        if p.delta:
            w('}')
    w('')
    if derived:
        w('// ' + '-' * 76)
        w('// Load-image addresses of relocated blocks (used by the init copy loops)')
        w('// ' + '-' * 76)
        o.extend(derived)
        w('')
    for ln in A.POSTAMBLE.strip('\n').splitlines():
        w(ln)
    open(path, 'w').write('\n'.join(o) + '\n')
    for f_, lines_ in files.items():
        fp = os.path.join(os.path.dirname(path), f_) if path != os.devnull else os.devnull
        open(fp, 'w').write('\n'.join(lines_) + '\n')
    return o + [x for v in files.values() for x in v]


used_names_out = set()
used_ram_tables = set()
split_ends = {e for (a, e, f, d) in A.SPLITS}


def format_data(l, e, fm):
    if fm is None:
        return data_lines(l, e)
    kindf, *args = fm
    out = []
    if kindf == 'words':          # little-endian address words
        i = l
        while i + 1 < e:
            v = IMG[i] | IMG[i + 1] << 8
            out.append((i, '.word ' + (ref(v) or hexv(v, 4)), ''))
            i += 2
        if i < e:
            out += data_lines(i, e)
        return out
    if kindf == 'words_num':      # plain 16-bit numbers, 8 per line
        i = l
        while i + 1 < e:
            j = min(e - (e - i) % 2, i + 16)
            out.append((i, '.word ' + ','.join('$%04x' % (IMG[k] | IMG[k + 1] << 8) for k in range(i, j, 2)), ''))
            i = j
        if i < e:
            out += data_lines(i, e)
        return out
    if kindf == 'lo' or kindf == 'hi':    # split pointer tables: args = (other_table_rt,)
        other = args[0]
        for i in range(l, e):
            r = piece_of[i].rt(i)
            o = rt2load[other + (r - piece_of[l].rt(l))]
            lo, hi = (IMG[i], IMG[o]) if kindf == 'lo' else (IMG[o], IMG[i])
            v = lo | hi << 8
            s = ref(v) or hexv(v, 4)
            out.append((i, '.byte %s(%s)' % ('<' if kindf == 'lo' else '>', s), ''))
        return out
    if kindf == 'rows':           # fixed width rows
        wdt = args[0]
        i = l
        while i < e:
            j = min(e, i + wdt)
            out.append((i, '.byte ' + ','.join('$%02x' % b for b in IMG[i:j]), ''))
            i = j
        return out
    if kindf == 'text':           # ASCII-ish text, show as comment
        i = l
        while i < e:
            j = min(e, i + 16)
            txt = ''.join(chr(b) if 32 <= b < 127 else '.' for b in IMG[i:j])
            out.append((i, '.byte ' + ','.join('$%02x' % b for b in IMG[i:j]), '"%s"' % txt))
            i = j
        return out
    if kindf == 'sprites':        # 64-byte sprites: 21 rows of 3 bytes + 1 pad byte
        i = l
        base = piece_of[l].rt(l)
        while i + 64 <= e:
            nr = (piece_of[i].rt(i) & 0x3fff) // 64
            out.append((i, '// sprite $%02x' % nr, ''))
            for row in range(21):
                b = IMG[i + row * 3:i + row * 3 + 3]
                pic = ''.join(format(x, '08b') for x in b).replace('0', '.').replace('1', '#')
                out.append((i + row * 3, '.byte ' + ','.join('%%%s' % format(x, '08b') for x in b), pic))
            out.append((i + 63, '.byte $%02x' % IMG[i + 63], ''))
            i += 64
        if i < e:
            out += data_lines(i, e)
        return out
    if kindf == 'bin':            # graphics: one byte per line as binary
        for i in range(l, e):
            b = IMG[i]
            out.append((i, '.byte %%%s' % format(b, '08b'), format(b, '08b').replace('0', '.').replace('1', '#')))
        return out
    raise ValueError(fm)


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'src/thrust.asm')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    find_imm_pairs()
    txt = '\n'.join(emit(os.devnull))      # pass 1: collect auto labels + used names
    used_names_out.update(re.findall(r'[A-Za-z_][A-Za-z0-9_]*', txt.split('* = $')[1]))
    emit(out)
    ncode = sum(1 for l in range(LOAD0, LOAD_END) if kind[l] in (CODE, OPER))
    print('code bytes %d, data bytes %d, labels %d, problems %d' % (ncode, LOAD_END - LOAD0 - ncode, len(labels), len(problems)))
    with open(os.path.join(ROOT, 'build/problems.txt') if os.path.isdir(os.path.join(ROOT, 'build')) else os.devnull, 'w') as f:
        f.write('\n'.join(problems))
    for p in problems[:40]:
        print('  ', p)
