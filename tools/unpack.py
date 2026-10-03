"""Run the packed thrust.prg through the 6502 emulator until the decruncher
hands over to BASIC (RUN), then save the unpacked program as a PRG."""
import sys
sys.path.insert(0, 'tools')
from cpu6502 import CPU
d = open(sys.argv[1], 'rb').read()
la = d[0] | d[1] << 8
cpu = CPU()
cpu.m[la:la + len(d) - 2] = d[2:]
cpu.m[1] = 0x37
cpu.pc = 0x080c          # SYS pi*656
writes = set()
stage = [0]
cpu.write_hook = lambda a, v: writes.add(a) if stage[0] else None
while not (cpu.pc >= 0xa000):
    if cpu.pc == 0x0439:  # final-stage decruncher entry
        stage[0] = 1
    cpu.step()
lo = min(a for a in writes if a >= 0x0801)
hi = max(a for a in writes if a < 0xa000)
print('entry %04x, unpacked %04x-%04x' % (cpu.pc, lo, hi))
# basic end pointer ($2d/$2e) set by decruncher tells the real program end
end = cpu.m[0x2d] | cpu.m[0x2e] << 8
print('basic end ptr %04x' % end)
open(sys.argv[2], 'wb').write(bytes([0x01, 0x08]) + bytes(cpu.m[0x0801:end]))
