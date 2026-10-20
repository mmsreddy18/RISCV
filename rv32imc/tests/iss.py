#!/usr/bin/env python3
"""Minimal RV32IM reference ISS (32-bit encodings only) used for differential testing.
Usage: iss.py prog.bin out.txt
Dump format matches tb_core.sv: 'x<n> <hex>' for x1..x31 and 'm<addr> <hex>' for 256 words @0x4000.
"""
import sys
M = 0xFFFFFFFF
MEM_BYTES = 256 * 1024
TOHOST = 0x10000000

def s32(v):
    v &= M
    return v - (1 << 32) if v & 0x80000000 else v

def sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v & (1 << (bits - 1)) else v

def run(binfile, maxsteps=2_000_000):
    mem = bytearray(MEM_BYTES)
    data = open(binfile, "rb").read()
    mem[:len(data)] = data
    x = [0] * 32
    pc = 0

    def rd32(a):
        a &= M
        assert a + 4 <= MEM_BYTES, "bad load addr %08x" % a
        return int.from_bytes(mem[a:a + 4], "little")

    for _ in range(maxsteps):
        ins = rd32(pc)
        opc = ins & 0x7F
        rd = (ins >> 7) & 31
        f3 = (ins >> 12) & 7
        rs1 = (ins >> 15) & 31
        rs2 = (ins >> 20) & 31
        f7 = ins >> 25
        a, b = x[rs1], x[rs2]
        npc = (pc + 4) & M
        res = None
        if opc == 0x37:
            res = ins & 0xFFFFF000
        elif opc == 0x17:
            res = (pc + (ins & 0xFFFFF000)) & M
        elif opc == 0x6F:
            imm = sext(((ins >> 31) << 20) | (((ins >> 12) & 0xFF) << 12) |
                       (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21)
            res = npc
            npc = (pc + imm) & M
        elif opc == 0x67:
            imm = sext(ins >> 20, 12)
            res = npc
            npc = (a + imm) & M & ~1
        elif opc == 0x63:
            imm = sext(((ins >> 31) << 12) | (((ins >> 7) & 1) << 11) |
                       (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13)
            t = {0: a == b, 1: a != b, 4: s32(a) < s32(b), 5: s32(a) >= s32(b),
                 6: a < b, 7: a >= b}[f3]
            if t:
                npc = (pc + imm) & M
        elif opc == 0x03:
            addr = (a + sext(ins >> 20, 12)) & M
            if f3 == 0:   res = sext(mem[addr], 8) & M
            elif f3 == 4: res = mem[addr]
            elif f3 == 1: res = sext(int.from_bytes(mem[addr:addr + 2], "little"), 16) & M
            elif f3 == 5: res = int.from_bytes(mem[addr:addr + 2], "little")
            elif f3 == 2: res = rd32(addr)
            else: raise Exception("bad load")
        elif opc == 0x23:
            addr = (a + sext(((ins >> 25) << 5) | ((ins >> 7) & 0x1F), 12)) & M
            if addr == TOHOST:
                return x, mem
            n = {0: 1, 1: 2, 2: 4}[f3]
            mem[addr:addr + n] = (b & ((1 << (8 * n)) - 1)).to_bytes(n, "little")
        elif opc == 0x13:
            imm = sext(ins >> 20, 12)
            if   f3 == 0: res = (a + imm) & M
            elif f3 == 2: res = int(s32(a) < imm)
            elif f3 == 3: res = int(a < (imm & M))
            elif f3 == 4: res = (a ^ imm) & M
            elif f3 == 6: res = (a | imm) & M
            elif f3 == 7: res = (a & imm) & M
            elif f3 == 1: res = (a << rs2) & M
            elif f3 == 5: res = (a >> rs2) if f7 == 0 else (s32(a) >> rs2) & M
        elif opc == 0x33:
            if f7 == 1:
                sa, sb = s32(a), s32(b)
                if   f3 == 0: res = (a * b) & M
                elif f3 == 1: res = ((sa * sb) >> 32) & M
                elif f3 == 2: res = ((sa * b) >> 32) & M
                elif f3 == 3: res = ((a * b) >> 32) & M
                elif f3 == 4:
                    if b == 0: res = M
                    elif sa == -(1 << 31) and sb == -1: res = a
                    else:
                        q = abs(sa) // abs(sb)
                        res = (-q if (sa < 0) != (sb < 0) else q) & M
                elif f3 == 5: res = M if b == 0 else a // b
                elif f3 == 6:
                    if b == 0: res = a
                    elif sa == -(1 << 31) and sb == -1: res = 0
                    else:
                        q = abs(sa) // abs(sb)
                        q = -q if (sa < 0) != (sb < 0) else q
                        res = (sa - q * sb) & M
                elif f3 == 7: res = a if b == 0 else a % b
            else:
                if   f3 == 0: res = (a - b) & M if f7 == 0x20 else (a + b) & M
                elif f3 == 1: res = (a << (b & 31)) & M
                elif f3 == 2: res = int(s32(a) < s32(b))
                elif f3 == 3: res = int(a < b)
                elif f3 == 4: res = a ^ b
                elif f3 == 5: res = (a >> (b & 31)) if f7 == 0 else (s32(a) >> (b & 31)) & M
                elif f3 == 6: res = a | b
                elif f3 == 7: res = a & b
        elif opc == 0x0F:
            pass
        else:
            raise Exception("illegal instruction %08x at pc %08x" % (ins, pc))
        if res is not None and rd != 0:
            x[rd] = res & M
        pc = npc
    raise Exception("ISS timeout")

if __name__ == "__main__":
    x, mem = run(sys.argv[1])
    with open(sys.argv[2], "w") as f:
        for i in range(1, 32):
            f.write("x%d %08x\n" % (i, x[i]))
        for i in range(256):
            a = 0x4000 + 4 * i
            f.write("m%08x %08x\n" % (a, int.from_bytes(mem[a:a + 4], "little")))
