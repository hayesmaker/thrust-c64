"""Render the C64 screen (text/bitmap, hires/multicolour, sprites ignored)
from emulator state to a PNG."""
import zlib, struct
PAL = [(0,0,0),(255,255,255),(136,57,50),(103,182,189),(139,63,150),(85,160,73),(64,49,141),(191,206,114),
       (139,84,41),(87,66,0),(184,105,98),(80,80,80),(120,120,120),(148,224,137),(120,105,196),(159,159,159)]

def png(path, w, h, rows):
    raw = b''.join(b'\0' + bytes(sum((PAL[c] for c in r), ())) for r in rows)
    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))

def render(c, path):
    from emu import CHAR
    rows = []
    bank = (3 - (c.io[0xd00] & 3)) * 0x4000
    for y in range(200):
        io = bytearray(c.io)
        io[0x11:0x24] = c.lineregs[y]
        scr = bank + ((io[0x18] >> 4) & 15) * 0x400
        d011, d016 = io[0x11], io[0x16]
        bmm, mcm = d011 & 0x20, d016 & 0x10
        bmp = bank + (0x2000 if io[0x18] & 8 else 0)
        chb = bank + ((io[0x18] >> 1) & 7) * 0x800
        row = []
        cy, ly = y >> 3, y & 7
        for cx in range(40):
            sc = c.m[scr + cy * 40 + cx]
            col = c.io[0x800 + cy * 40 + cx] & 15
            if bmm:
                b = c.m[bmp + (cy * 40 + cx) * 8 + ly]
            else:
                a = chb + sc * 8 + ly
                b = CHAR[(a & 0xfff)] if (a & 0x7000) == 0x1000 and bank in (0, 0x8000) else c.m[a]
            if mcm and (bmm or col & 8):
                cols = [io[0x21] & 15, (sc >> 4) if bmm else io[0x22] & 15, (sc & 15) if bmm else io[0x23] & 15, col & (15 if bmm else 7)]
                for px in range(4):
                    v = cols[(b >> (6 - px * 2)) & 3]; row += [v, v]
            else:
                fg, bg = ((sc >> 4), sc & 15) if bmm else (col, io[0x21] & 15)
                for px in range(8):
                    row.append(fg if (b >> (7 - px)) & 1 else bg)
        rows.append(row)
    png(path, 320, 200, rows)
