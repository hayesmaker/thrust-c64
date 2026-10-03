"""Report data regions with their access status, to find unreached code."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import disasm as D
COPY = {0x6c44, 0xb697, 0xb6ea, 0xb6f0, 0xb6f6, 0xb6fc, 0xb707, 0xb72d, 0xb73d, 0xb748, 0x046b}
rd = {a: s - COPY for a, s in D.rd_log.items() if s - COPY}
for p in D.PIECES:
    if p.name in D.A.RAW_PIECES or p.name in ('gfx',):
        continue
    l = p.lstart
    while l < p.lend:
        if D.kind[l] in (D.CODE, D.OPER):
            l += 1; continue
        e = l
        while e < p.lend and D.kind[e] not in (D.CODE, D.OPER):
            e += 1
        r0 = p.rt(l)
        nread = sum(1 for i in range(l, e) if p.rt(i) in rd)
        # how far does it decode as plausible code?
        i = l; ok = 0
        while i < e:
            t = D.try_insn(i)
            if not t: break
            ok += 1; i += t[2]
            if t[0] in ('rts', 'jmp', 'rti'): break
        print('%04x-%04x len %4d read %4d  decodes %3d insns%s' % (r0, p.rt(e - 1), e - l, nread, ok, ' <-- ends rts/jmp' if i <= e and ok > 2 and D.try_insn(i - (D.try_insn(i-1) and 0 or 0)) else ''))
        l = e
