#!/usr/bin/env python3
"""Random RV32IM program generator for differential testing (assembly output).
Programs only use forward branches/jumps and bounded loops, so they always terminate.
x8 = data base (never written), x1/x28 used for link/target (cleared at end),
x29 = loop counter, x30/x31 = tohost.
"""
import random, sys

POOL_ALL = [5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]
CONSTS = [0, 1, -1, 2, 3, 7, -8, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFF, 0x10000,
          0x55555555, 0xAAAAAAAA, 100, -100, 31, 32, 0x12345678, 0xDEADBEEF]

RR  = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
RI  = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SH  = ["slli", "srli", "srai"]
MUL = ["mul", "mulh", "mulhsu", "mulhu"]
DIV = ["div", "divu", "rem", "remu"]
BR  = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]

def gen(seed, n_items=220):
    r = random.Random(seed)
    friendly = (seed % 2 == 0)       # bias toward RVC-compressible forms
    POOL = POOL_ALL if not friendly else [9, 10, 11, 12, 13, 14, 15, 5]
    out = []
    recent = []
    lab = [0]

    def newlab():
        lab[0] += 1
        return "L%d" % lab[0]

    def pick(bias=True):
        if bias and recent and r.random() < 0.45:
            return r.choice(recent[-3:])
        return r.choice(POOL)

    def dest():
        if r.random() < 0.03:
            return 0
        d = r.choice(POOL)
        recent.append(d)
        return d

    def imm12():
        if r.random() < 0.7:
            return r.randint(-32, 31)
        return r.randint(-2048, 2047)

    def dest_like(a):
        # rd == rs1 with some probability (enables c.add/c.sub/c.addi/c.slli ...)
        if friendly and r.random() < 0.55 and a in POOL:
            recent.append(a)
            return a
        return dest()

    def simple():
        k = r.random()
        if k < 0.45:
            a = pick()
            return "%s x%d, x%d, x%d" % (r.choice(RR), dest_like(a), a, pick())
        if k < 0.75:
            a = pick()
            return "%s x%d, x%d, %d" % (r.choice(RI), dest_like(a), a, imm12())
        if k < 0.85:
            a = pick()
            return "%s x%d, x%d, %d" % (r.choice(SH), dest_like(a), a, r.randint(0, 31))
        if k < 0.9:
            return "lui x%d, %d" % (dest(), r.randint(0, 0xFFFFF))
        if k < 0.95:
            return "%s x%d, x%d, x%d" % (r.choice(MUL), dest(), pick(), pick())
        return "%s x%d, x%d, x%d" % (r.choice(DIV), dest(), pick(), pick())

    def memop():
        k = r.random()
        base = 8
        if k < 0.35:
            off = 4 * r.randint(0, 63)
            return ["lw x%d, %d(x8)" % (dest(), off)]
        if k < 0.6:
            off = 4 * r.randint(0, 63)
            return ["sw x%d, %d(x8)" % (pick(), off)]
        if k < 0.7:
            return ["lh%s x%d, %d(x8)" % (r.choice(["", "u"]), dest(), 2 * r.randint(0, 127))]
        if k < 0.78:
            return ["sh x%d, %d(x8)" % (pick(), 2 * r.randint(0, 127))]
        if k < 0.9:
            return ["lb%s x%d, %d(x8)" % (r.choice(["", "u"]), dest(), r.randint(0, 255))]
        return ["sb x%d, %d(x8)" % (pick(), r.randint(0, 255))]

    # ---- prologue
    out.append(".section .text.init")
    out.append(".globl _start")
    out.append("_start:")
    out.append("  li x8, 0x4000")
    for p in POOL:
        out.append("  li x%d, %d" % (p, r.choice(CONSTS) if r.random() < 0.7 else r.getrandbits(32) - (1 << 31)))
    recent.extend(POOL[:3])

    # ---- body
    for _ in range(n_items):
        k = r.random()
        if k < 0.50:
            out.append("  " + simple())
        elif k < 0.68:
            out.extend("  " + s for s in memop())
        elif k < 0.80:   # forward conditional branch over a few instructions
            L = newlab()
            if r.random() < 0.15:
                out.append("  %s x%d, x0, %s" % (r.choice(["beq", "bne"]), pick(), L))
            else:
                out.append("  %s x%d, x%d, %s" % (r.choice(BR), pick(), pick(), L))
            for _ in range(r.randint(1, 4)):
                out.append("  " + (simple() if r.random() < 0.7 else memop()[0]))
            out.append(L + ":")
        elif k < 0.85:   # forward jump
            L = newlab()
            if r.random() < 0.5:
                out.append("  j %s" % L)
            else:
                out.append("  jal x1, %s" % L)
            for _ in range(r.randint(1, 3)):
                out.append("  " + simple())
            out.append(L + ":")
        elif k < 0.89:   # computed jump via jalr
            L = newlab()
            out.append("  la x28, %s" % L)
            out.append("  jalr x1, 0(x28)")
            for _ in range(r.randint(1, 3)):
                out.append("  " + simple())
            out.append(L + ":")
        elif k < 0.95:   # short bounded loop
            L = newlab()
            out.append("  li x29, %d" % r.randint(1, 5))
            out.append(L + ":")
            for _ in range(r.randint(2, 5)):
                out.append("  " + (simple() if r.random() < 0.75 else memop()[0]))
            out.append("  addi x29, x29, -1")
            out.append("  bnez x29, %s" % L)
        else:            # dependent chain: load-use / mul-use / div-use
            d = dest()
            kind = r.choice(["lw", "mul", "div"])
            if kind == "lw":
                out.append("  lw x%d, %d(x8)" % (d, 4 * r.randint(0, 63)))
            elif kind == "mul":
                out.append("  %s x%d, x%d, x%d" % (r.choice(MUL), d, pick(), pick()))
            else:
                out.append("  %s x%d, x%d, x%d" % (r.choice(DIV), d, pick(), pick()))
            out.append("  add x%d, x%d, x%d" % (dest(), d, pick()))
            out.append("  add x%d, x%d, x%d" % (dest(), d, d))

    # ---- epilogue
    out.append("  li x1, 0")
    out.append("  li x28, 0")
    out.append("  li x29, 0")
    out.append("  li x30, 1")
    out.append("  lui x31, 0x10000")
    out.append("  sw x30, 0(x31)")
    out.append("1: j 1b")
    out.append(".section .data")
    out.append(".balign 4")
    out.append("buf:")
    for _ in range(64):
        out.append("  .word 0x%08x" % r.getrandbits(32))
    return "\n".join(out) + "\n"

if __name__ == "__main__":
    sys.stdout.write(gen(int(sys.argv[1])))
