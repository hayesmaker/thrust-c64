"""Minimal 6502 emulator + opcode table, used to unpack the Thrust PRG and
to drive the disassembler. Documented opcodes only (illegal opcodes raise)."""

# mode: size
MODES = {
    'imp': 1, 'acc': 1, 'imm': 2, 'zp': 2, 'zpx': 2, 'zpy': 2,
    'izx': 2, 'izy': 2, 'rel': 2, 'abs': 3, 'abx': 3, 'aby': 3, 'ind': 3,
}

_TABLE = """
00 brk imp|01 ora izx|05 ora zp|06 asl zp|08 php imp|09 ora imm|0a asl acc|0d ora abs|0e asl abs
10 bpl rel|11 ora izy|15 ora zpx|16 asl zpx|18 clc imp|19 ora aby|1d ora abx|1e asl abx
20 jsr abs|21 and izx|24 bit zp|25 and zp|26 rol zp|28 plp imp|29 and imm|2a rol acc|2c bit abs|2d and abs|2e rol abs
30 bmi rel|31 and izy|35 and zpx|36 rol zpx|38 sec imp|39 and aby|3d and abx|3e rol abx
40 rti imp|41 eor izx|45 eor zp|46 lsr zp|48 pha imp|49 eor imm|4a lsr acc|4c jmp abs|4d eor abs|4e lsr abs
50 bvc rel|51 eor izy|55 eor zpx|56 lsr zpx|58 cli imp|59 eor aby|5d eor abx|5e lsr abx
60 rts imp|61 adc izx|65 adc zp|66 ror zp|68 pla imp|69 adc imm|6a ror acc|6c jmp ind|6d adc abs|6e ror abs
70 bvs rel|71 adc izy|75 adc zpx|76 ror zpx|78 sei imp|79 adc aby|7d adc abx|7e ror abx
81 sta izx|84 sty zp|85 sta zp|86 stx zp|88 dey imp|8a txa imp|8c sty abs|8d sta abs|8e stx abs
90 bcc rel|91 sta izy|94 sty zpx|95 sta zpx|96 stx zpy|98 tya imp|99 sta aby|9a txs imp|9d sta abx
a0 ldy imm|a1 lda izx|a2 ldx imm|a4 ldy zp|a5 lda zp|a6 ldx zp|a8 tay imp|a9 lda imm|aa tax imp|ac ldy abs|ad lda abs|ae ldx abs
b0 bcs rel|b1 lda izy|b4 ldy zpx|b5 lda zpx|b6 ldx zpy|b8 clv imp|b9 lda aby|ba tsx imp|bc ldy abx|bd lda abx|be ldx aby
c0 cpy imm|c1 cmp izx|c4 cpy zp|c5 cmp zp|c6 dec zp|c8 iny imp|c9 cmp imm|ca dex imp|cc cpy abs|cd cmp abs|ce dec abs
d0 bne rel|d1 cmp izy|d5 cmp zpx|d6 dec zpx|d8 cld imp|d9 cmp aby|dd cmp abx|de dec abx
e0 cpx imm|e1 sbc izx|e4 cpx zp|e5 sbc zp|e6 inc zp|e8 inx imp|e9 sbc imm|ea nop imp|ec cpx abs|ed sbc abs|ee inc abs
f0 beq rel|f1 sbc izy|f5 sbc zpx|f6 inc zpx|f8 sed imp|f9 sbc aby|fd sbc abx|fe inc abx
"""

OPS = {}
for line in _TABLE.strip().splitlines():
    for ent in line.split('|'):
        h, m, mode = ent.split()
        OPS[int(h, 16)] = (m, mode)


class CPU:
    def __init__(self, mem=None):
        self.m = mem if mem is not None else bytearray(65536)
        self.a = self.x = self.y = 0
        self.sp = 0xff
        self.pc = 0
        self.c = self.z = self.i = self.d = self.v = self.n = 0
        self.cycles = 0
        self.write_hook = None

    def rd(self, a):
        return self.m[a & 0xffff]

    def wr(self, a, v):
        a &= 0xffff
        if self.write_hook:
            self.write_hook(a, v)
        self.m[a] = v & 0xff

    def rw(self, a):
        return self.rd(a) | (self.rd(a + 1) << 8)

    def push(self, v):
        self.m[0x100 + self.sp] = v & 0xff
        self.sp = (self.sp - 1) & 0xff

    def pull(self):
        self.sp = (self.sp + 1) & 0xff
        return self.m[0x100 + self.sp]

    def p(self):
        return (self.n << 7) | (self.v << 6) | 0x20 | 0x10 | (self.d << 3) | (self.i << 2) | (self.z << 1) | self.c

    def setp(self, v):
        self.n, self.v = (v >> 7) & 1, (v >> 6) & 1
        self.d, self.i, self.z, self.c = (v >> 3) & 1, (v >> 2) & 1, (v >> 1) & 1, v & 1

    def nz(self, v):
        v &= 0xff
        self.n = v >> 7
        self.z = int(v == 0)
        return v

    def addr(self, mode):
        pc = self.pc
        if mode == 'imm':
            return pc + 1
        if mode == 'zp':
            return self.rd(pc + 1)
        if mode == 'zpx':
            return (self.rd(pc + 1) + self.x) & 0xff
        if mode == 'zpy':
            return (self.rd(pc + 1) + self.y) & 0xff
        if mode == 'abs':
            return self.rw(pc + 1)
        if mode == 'abx':
            return (self.rw(pc + 1) + self.x) & 0xffff
        if mode == 'aby':
            return (self.rw(pc + 1) + self.y) & 0xffff
        if mode == 'izx':
            z = (self.rd(pc + 1) + self.x) & 0xff
            return self.rd(z) | (self.rd((z + 1) & 0xff) << 8)
        if mode == 'izy':
            z = self.rd(pc + 1)
            return ((self.rd(z) | (self.rd((z + 1) & 0xff) << 8)) + self.y) & 0xffff
        if mode == 'ind':
            a = self.rw(pc + 1)
            return self.rd(a) | (self.rd((a & 0xff00) | ((a + 1) & 0xff)) << 8)
        return None

    def adc(self, v):
        if self.d:
            lo = (self.a & 0xf) + (v & 0xf) + self.c
            if lo > 9:
                lo += 6
            hi = (self.a >> 4) + (v >> 4) + (lo > 0xf)
            self.z = int(((self.a + v + self.c) & 0xff) == 0)
            self.n = (hi >> 3) & 1
            self.v = int(((self.a ^ v) & 0x80) == 0 and ((self.a ^ (hi << 4)) & 0x80) != 0)
            if hi > 9:
                hi += 6
            self.c = int(hi > 0xf)
            self.a = ((hi << 4) | (lo & 0xf)) & 0xff
            return
        r = self.a + v + self.c
        self.v = int(((self.a ^ r) & (v ^ r) & 0x80) != 0)
        self.c = int(r > 0xff)
        self.a = self.nz(r)

    def sbc(self, v):
        if self.d:
            r = self.a - v - (1 - self.c)
            lo = (self.a & 0xf) - (v & 0xf) - (1 - self.c)
            hi = (self.a >> 4) - (v >> 4)
            if lo < 0:
                lo -= 6
                hi -= 1
            if hi < 0:
                hi -= 6
            self.c = int(r >= 0)
            self.nz(r)
            self.v = int(((self.a ^ v) & (self.a ^ r) & 0x80) != 0)
            self.a = ((hi << 4) | (lo & 0xf)) & 0xff
            return
        self.adc(v ^ 0xff)

    def cmp(self, r, v):
        t = r - v
        self.c = int(t >= 0)
        self.nz(t)

    def step(self):
        op = self.rd(self.pc)
        if op not in OPS:
            raise RuntimeError('illegal opcode %02x at %04x' % (op, self.pc))
        m, mode = OPS[op]
        size = MODES[mode]
        ea = self.addr(mode)
        npc = (self.pc + size) & 0xffff
        self.cycles += 1
        if m == 'lda': self.a = self.nz(self.rd(ea))
        elif m == 'ldx': self.x = self.nz(self.rd(ea))
        elif m == 'ldy': self.y = self.nz(self.rd(ea))
        elif m == 'sta': self.wr(ea, self.a)
        elif m == 'stx': self.wr(ea, self.x)
        elif m == 'sty': self.wr(ea, self.y)
        elif m == 'tax': self.x = self.nz(self.a)
        elif m == 'tay': self.y = self.nz(self.a)
        elif m == 'txa': self.a = self.nz(self.x)
        elif m == 'tya': self.a = self.nz(self.y)
        elif m == 'tsx': self.x = self.nz(self.sp)
        elif m == 'txs': self.sp = self.x
        elif m == 'inx': self.x = self.nz(self.x + 1)
        elif m == 'iny': self.y = self.nz(self.y + 1)
        elif m == 'dex': self.x = self.nz(self.x - 1)
        elif m == 'dey': self.y = self.nz(self.y - 1)
        elif m == 'inc': self.wr(ea, self.nz(self.rd(ea) + 1))
        elif m == 'dec': self.wr(ea, self.nz(self.rd(ea) - 1))
        elif m == 'adc': self.adc(self.rd(ea))
        elif m == 'sbc': self.sbc(self.rd(ea))
        elif m == 'and': self.a = self.nz(self.a & self.rd(ea))
        elif m == 'ora': self.a = self.nz(self.a | self.rd(ea))
        elif m == 'eor': self.a = self.nz(self.a ^ self.rd(ea))
        elif m == 'cmp': self.cmp(self.a, self.rd(ea))
        elif m == 'cpx': self.cmp(self.x, self.rd(ea))
        elif m == 'cpy': self.cmp(self.y, self.rd(ea))
        elif m == 'bit':
            v = self.rd(ea)
            self.n, self.v, self.z = (v >> 7) & 1, (v >> 6) & 1, int((v & self.a) == 0)
        elif m in ('asl', 'lsr', 'rol', 'ror'):
            v = self.a if mode == 'acc' else self.rd(ea)
            if m == 'asl': self.c, v = v >> 7, v << 1
            elif m == 'lsr': self.c, v = v & 1, v >> 1
            elif m == 'rol': self.c, v = v >> 7, (v << 1) | self.c
            else: self.c, v = v & 1, (v >> 1) | (self.c << 7)
            v = self.nz(v)
            if mode == 'acc': self.a = v
            else: self.wr(ea, v)
        elif m == 'rel' or mode == 'rel':
            off = self.rd(self.pc + 1)
            off = off - 256 if off & 0x80 else off
            cond = {'bpl': not self.n, 'bmi': self.n, 'bvc': not self.v, 'bvs': self.v,
                    'bcc': not self.c, 'bcs': self.c, 'bne': not self.z, 'beq': self.z}[m]
            if cond:
                npc = (npc + off) & 0xffff
        elif m == 'jmp': npc = ea
        elif m == 'jsr':
            r = (self.pc + 2) & 0xffff
            self.push(r >> 8); self.push(r)
            npc = ea
        elif m == 'rts':
            lo = self.pull(); hi = self.pull()
            npc = ((hi << 8) | lo) + 1 & 0xffff
        elif m == 'rti':
            self.setp(self.pull())
            lo = self.pull(); hi = self.pull()
            npc = (hi << 8) | lo
        elif m == 'brk':
            raise RuntimeError('BRK at %04x' % self.pc)
        elif m == 'pha': self.push(self.a)
        elif m == 'php': self.push(self.p())
        elif m == 'pla': self.a = self.nz(self.pull())
        elif m == 'plp': self.setp(self.pull())
        elif m == 'clc': self.c = 0
        elif m == 'sec': self.c = 1
        elif m == 'cli': self.i = 0
        elif m == 'sei': self.i = 1
        elif m == 'cld': self.d = 0
        elif m == 'sed': self.d = 1
        elif m == 'clv': self.v = 0
        elif m == 'nop': pass
        else:
            raise RuntimeError('unimplemented %s' % m)
        self.pc = npc
