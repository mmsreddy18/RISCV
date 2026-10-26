#!/usr/bin/env python3
"""Split a combined program image (one 32-bit hex word per line, address 0 first) into the two memory images of
rv32imc_sys.   usage: split_hex.py <program.hex> <imem.hex> <dmem.hex> [imem_bytes=32768] [dmem_base=0x10000] [dmem_bytes=32768]"""
import sys
src, fi, fd = sys.argv[1:4]
ib = int(sys.argv[4], 0) if len(sys.argv) > 4 else 32768
db = int(sys.argv[5], 0) if len(sys.argv) > 5 else 0x10000
dn = int(sys.argv[6], 0) if len(sys.argv) > 6 else 32768
w = [l.strip() for l in open(src) if l.strip()]
im = w[: ib // 4]
dm = w[db // 4 : db // 4 + dn // 4]
if len(w) * 4 > db + dn: sys.exit("program does not fit the memories")
if len(w) * 4 > ib and len(w) * 4 <= db: pass
open(fi, "w").write("\n".join(im) + "\n")
open(fd, "w").write("\n".join(dm) + ("\n" if dm else ""))
print(f"imem {len(im)} words, dmem {len(dm)} words")
