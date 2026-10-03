import sys
sys.path.insert(0, 'tools')
from cpu6502 import OPS, MODES
def dis(m, start, end):
    pc = start
    while pc < end:
        op = m[pc]
        if op not in OPS:
            print('%04x  %02x        .byte $%02x' % (pc, op, op)); pc += 1; continue
        mn, mode = OPS[op]; n = MODES[mode]
        b = m[pc:pc+n]; a = b[1] if n > 1 else 0; w = a | (b[2] << 8) if n == 3 else 0
        arg = {'imp':'','acc':'a','imm':'#$%02x'%a,'zp':'$%02x'%a,'zpx':'$%02x,x'%a,'zpy':'$%02x,y'%a,
               'izx':'($%02x,x)'%a,'izy':'($%02x),y'%a,'rel':'$%04x'%((pc+2+(a-256 if a>127 else a))&0xffff),
               'abs':'$%04x'%w,'abx':'$%04x,x'%w,'aby':'$%04x,y'%w,'ind':'($%04x)'%w}[mode]
        print('%04x  %-9s %s %s' % (pc, ' '.join('%02x'%x for x in b), mn, arg)); pc += n
if __name__ == '__main__':
    m = open(sys.argv[1],'rb').read()
    dis(m, int(sys.argv[2],16), int(sys.argv[3],16))
