"""Run the game in the crude emulator with scripted/random input and save
coverage (executed PCs + data refs) to a pickle for the disassembler."""
import sys, random, pickle, time
sys.path.insert(0, 'tools')
from emu import boot
random.seed(int(sys.argv[3]) if len(sys.argv) > 3 else 1)
c = boot(sys.argv[1])
total = int(sys.argv[2])
t = time.time()
last = 0
joy = 0xff
while c.frame < total:
    f = c.frame
    if f != last:
        last = f
        if f % 50 == 0:
            print('frame', f, 'pcs', len(c.exec_pcs), '%.0fs' % (time.time() - t), flush=True)
        phase = f % 3000
        if phase < 600:
            joy = 0xff                      # let attract mode run
        elif phase < 620:
            joy = 0xef                      # fire to start
        elif f % 25 == 0:
            # random joystick: bits 0-3 dirs, bit4 fire (active low)
            joy = 0xff & ~random.choice([0, 1, 2, 4, 8, 0x10, 0x11, 0x14, 0x18, 0x01, 0x05, 0x09])
        c.joy = joy
        # occasionally tap keys (space / F-keys / run-stop) to explore menus
        c.keys = set()
        if f % 3000 in range(590, 600):
            c.keys = {(7, 4)}               # space
    c.run_cycles(1000)
pickle.dump({'exec': c.exec_pcs, 'rd': c.rd_log, 'wr': c.wr_log, 'ptr': c.ptr_log, 'ind': c.ind_jumps}, open(sys.argv[4] if len(sys.argv) > 4 else 'coverage.pkl', 'wb'))
print('done', len(c.exec_pcs))
