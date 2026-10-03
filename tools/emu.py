"""Crude C64 emulation for code-coverage gathering.
Banks ROMs per $01, emulates VIC raster IRQ, CIA1 timer A IRQ, joystick in
port 2. Records every executed PC and every data read address."""
import sys, random, pickle
sys.path.insert(0, 'tools')
from cpu6502 import CPU, OPS, MODES

ROM = '/usr/lib/vice/'
BASIC = open(ROM + 'basic-901226-01.bin', 'rb').read()
KERNAL = open(ROM + 'kernal-901227-03.bin', 'rb').read()
CHAR = open(ROM + 'chargen-901225-01.bin', 'rb').read()

READS = {'lda', 'ldx', 'ldy', 'adc', 'sbc', 'and', 'ora', 'eor', 'cmp', 'cpx', 'cpy', 'bit',
         'asl', 'lsr', 'rol', 'ror', 'inc', 'dec'}
WRITES = {'sta', 'stx', 'sty', 'asl', 'lsr', 'rol', 'ror', 'inc', 'dec'}

# base cycle counts per addressing mode (approximate is fine)
CYC = {'imp': 2, 'acc': 2, 'imm': 2, 'zp': 3, 'zpx': 4, 'zpy': 4, 'izx': 6,
       'izy': 5, 'rel': 3, 'abs': 4, 'abx': 4, 'aby': 4, 'ind': 5}


class C64(CPU):
    def __init__(self):
        super().__init__()
        self.io = bytearray(0x1000)
        self.raster = 0
        self.rcyc = 0
        self.vic_irq = 0
        self.cia1_ta = 0xffff
        self.cia1_latch = 0xffff
        self.cia1_icr_mask = 0
        self.cia1_icr = 0
        self.cia1_run = 0
        self.joy = 0xff
        self.keys = set()          # (col,row) pressed
        self.exec_pcs = {}         # pc -> bytes executed
        self.rd_log = {}
        self.wr_log = {}
        self.ptr_log = {}
        self.ind_jumps = {}
        self.frame = 0
        self.lineregs = [bytes(0x13)] * 200

    def banks(self):
        p = self.m[1] & 7
        basic = (p & 3) == 3
        kernal = (p & 2) != 0
        io = (p & 3) != 0 and p != 0 and p >= 4 or p in (5, 6, 7)
        io = p in (5, 6, 7)
        chr_ = p in (1, 2, 3)
        return basic, kernal, io, chr_

    def is_ram(self, a):
        basic, kernal, io, chr_ = self.banks()
        if a < 0xa000 or 0xc000 <= a < 0xd000: return True
        if a < 0xc000: return not basic
        if a < 0xe000: return not (io or chr_)
        return not kernal

    def rd(self, a):
        a &= 0xffff
        if a >= 0xa000:
            basic, kernal, io, chr_ = self.banks()
            if a < 0xc000:
                if basic: return BASIC[a - 0xa000]
            elif 0xd000 <= a < 0xe000:
                if io: return self.io_rd(a)
                if chr_: return CHAR[a - 0xd000]
            elif a >= 0xe000:
                if kernal: return KERNAL[a - 0xe000]
        return self.m[a]

    def wr(self, a, v):
        a &= 0xffff
        v &= 0xff
        if 0xd000 <= a < 0xe000 and self.banks()[2]:
            self.io_wr(a, v)
            return
        self.m[a] = v

    def io_rd(self, a):
        r = a & 0xfff
        if r < 0x400:
            r &= 0x3f
            if r == 0x11: return (self.io[0x11] & 0x7f) | ((self.raster >> 1) & 0x80)
            if r == 0x12: return self.raster & 0xff
            if r == 0x19: return self.vic_irq | (0x80 if self.vic_irq else 0) | 0x70
            if r in (0x1e, 0x1f):
                v = self.io[r]; self.io[r] = 0; return v
            return self.io[r]
        if r < 0x800:  # SID
            r &= 0x1f
            if r == 0x1b: return random.randint(0, 255)
            if r == 0x1c: return 0
            return 0
        if 0xc00 <= r < 0xd00:  # CIA1
            r &= 0xf
            if r == 0: return self.joy
            if r == 1:
                cols = self.io[0xc00]
                v = 0xff
                for (c, rw) in self.keys:
                    if not (cols >> c) & 1: v &= ~(1 << rw)
                return v & 0xff
            if r == 4: return self.cia1_ta & 0xff
            if r == 5: return self.cia1_ta >> 8
            if r == 0xd:
                v = self.cia1_icr | (0x80 if self.cia1_icr & self.cia1_icr_mask else 0)
                self.cia1_icr = 0
                return v
            return self.io[0xc00 + r]
        if 0xd00 <= r < 0xe00:
            r &= 0xf
            if r == 0: return self.io[0xd00] | 0x00
            return self.io[0xd00 + r]
        return 0

    def io_wr(self, a, v):
        r = a & 0xfff
        if r < 0x400:
            r &= 0x3f
            if r == 0x19: self.vic_irq &= ~v & 0xf; return
            self.io[r] = v
            return
        if 0xc00 <= r < 0xd00:
            r &= 0xf
            if r == 4: self.cia1_latch = (self.cia1_latch & 0xff00) | v
            elif r == 5:
                self.cia1_latch = (self.cia1_latch & 0xff) | (v << 8)
                if not self.cia1_run: self.cia1_ta = self.cia1_latch
            elif r == 0xd:
                if v & 0x80: self.cia1_icr_mask |= v & 0x1f
                else: self.cia1_icr_mask &= ~v & 0x1f
            elif r == 0xe:
                self.cia1_run = v & 1
                if v & 0x10: self.cia1_ta = self.cia1_latch
            self.io[0xc00 + r] = v
            return
        self.io[r] = v

    def irq(self):
        r = (self.pc) & 0xffff
        self.push(r >> 8); self.push(r)
        self.push(self.p() & ~0x10)
        self.i = 1
        self.pc = self.rd(0xfffe) | (self.rd(0xffff) << 8)

    def nmi_vec(self):
        pass

    def run_cycles(self, n):
        end = self.cycles + n
        while self.cycles < end:
            pc = self.pc
            op = self.rd(pc)
            mn, mode = OPS[op]
            if self.is_ram(pc):
                if pc not in self.exec_pcs:
                    self.exec_pcs[pc] = bytes(self.m[pc:pc + MODES[mode]])
                if mode not in ('imp', 'acc', 'imm', 'rel'):
                    ea = self.addr(mode)
                    if mn in ('jmp', 'jsr'):
                        if mode == 'ind':
                            self.ind_jumps.setdefault(pc, set()).add(ea)
                    else:
                        if mn in READS:
                            self.rd_log.setdefault(ea, set()).add(pc)
                        if mn in WRITES:
                            self.wr_log.setdefault(ea, set()).add(pc)
                        if mode in ('izx', 'izy'):
                            z = self.m[pc + 1] + (self.x if mode == 'izx' else 0) & 0xff
                            self.ptr_log.setdefault(pc, set()).add(ea - (self.y if mode == 'izy' else 0) & 0xffff)
                            self.rd_log.setdefault(z, set()).add(pc)
                            self.rd_log.setdefault(z + 1 & 0xff, set()).add(pc)
            c0 = self.cycles
            self.step()
            dc = CYC[mode]
            self.cycles = c0 + dc
            # VIC raster
            self.rcyc += dc
            if self.rcyc >= 63:
                self.rcyc -= 63
                self.raster += 1
                if 51 <= self.raster < 251:
                    self.lineregs[self.raster - 51] = bytes(self.io[0x11:0x24])
                if self.raster >= 312:
                    self.raster = 0
                    self.frame += 1
                cmp_ = self.io[0x12] | ((self.io[0x11] & 0x80) << 1)
                if self.raster == cmp_:
                    self.vic_irq |= 1
            # CIA1 timer A
            if self.cia1_run:
                self.cia1_ta -= dc
                if self.cia1_ta <= 0:
                    self.cia1_ta += self.cia1_latch + 1
                    self.cia1_icr |= 1
            if not self.i:
                if (self.vic_irq & self.io[0x1a] & 0xf) or (self.cia1_icr & self.cia1_icr_mask):
                    self.irq()

    def step(self):
        # use our banked rd/wr via CPU core (CPU.step uses self.rd/self.wr)
        super().step()


def boot(prg):
    c = C64()
    d = open(prg, 'rb').read()
    c.m[0x0801:0x0801 + len(d) - 2] = d[2:]
    c.m[0] = 0x2f; c.m[1] = 0x37
    # minimal KERNAL vectors in RAM
    c.m[0x314:0x31a] = bytes([0x31, 0xea, 0x66, 0xfe, 0x47, 0xfe])
    c.pc = 0x6c24
    c.sp = 0xf6
    return c

if __name__ == '__main__':
    c = boot(sys.argv[1])
    frames = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    import time
    t = time.time()
    while c.frame < frames:
        c.run_cycles(19656)
    print('frames %d, %d unique pcs, %.1fs' % (c.frame, len(c.exec_pcs), time.time() - t))
