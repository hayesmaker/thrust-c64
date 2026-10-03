"""List unnamed data/zp references (and unnamed routines) per enclosing routine."""
import re, sys
lo, hi = int(sys.argv[1], 16), int(sys.argv[2], 16)
cur = None
for ln in open('src/thrust.asm'):
    m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):', ln)
    if m and not re.match(r'^L[0-9a-f]{4}$', m.group(1)):
        cur = m.group(1)
    m = re.search(r'// \$([0-9a-f]{4})', ln)
    if not m:
        continue
    a = int(m.group(1), 16)
    if not lo <= a < hi:
        continue
    code = ln.split('//')[0].strip()
    if code.startswith('.byte') or code.startswith('.word'):
        continue
    if re.search(r'\bD[0-9a-f]{4}\b|zp_tmp_|(?<!#)\$[0-9a-f]{2,4}\b|jsr L[0-9a-f]{4}', code):
        print('%-34s %04x  %s' % (cur, a, code))
