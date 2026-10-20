#!/usr/bin/env python3
"""Per-instruction latency / hazard-penalty microbenchmarks.

Each case is a loop of K unrolled copies of a small pattern. Running K=10 and K=30 and
differencing the cycle counts removes startup and loop overhead:
    cycles_per_unit = (cyc(K=30) - cyc(K=10)) / (20 * iterations)
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from common import *

ITERS = 20
# name, rvc?, unit text, instructions executed per unit, description
CASES = [
 ("alu_indep",       0, "add t0,a0,a1",                               1, "ALU, independent operands"),
 ("alu_dep",         0, "add a2,a2,a1",                               1, "ALU, back-to-back dependent (forwarding)"),
 ("load",            0, "lw t0,0(s0)",                                1, "load, independent"),
 ("load_use_0",      0, "lw t0,0(s0)\nadd t1,t0,t0",                  2, "load, consumer immediately after"),
 ("load_use_1",      0, "lw t0,0(s0)\nadd t2,a0,a1\nadd t1,t0,t0",    3, "load, one instruction between"),
 ("load_to_store",   0, "lw t0,0(s0)\nsw t0,4(s0)",                   2, "load feeding store data"),
 ("store",           0, "sw a0,4(s0)",                                1, "store"),
 ("store_load",      0, "sw a0,4(s0)\nlw t0,4(s0)",                   2, "store then load, same address"),
 ("br_not_taken",    0, "bne a0,a0,1f\n1:",                           1, "conditional branch, not taken"),
 ("br_taken",        0, "beq a0,a0,1f\n1:",                           1, "conditional branch, taken, word-aligned target"),
 ("br_taken_dep",    0, "addi t0,a0,0\nbeq t0,a0,1f\n1:",             2, "taken branch, operand from preceding ALU op"),
 ("br_taken_lduse",  0, "lw t0,0(s0)\nbeq t0,zero,1f\n1:",            2, "taken branch, operand from preceding load"),
 ("jal",             0, "jal zero,1f\n1:",                            1, "jal"),
 ("jalr",            0, "auipc t1,0\njalr zero,8(t1)",                2, "jalr (auipc + jalr to next unit)"),
 ("br_taken_word",   0, "beq a0,a0,1f\nnop\n1:\nadd t0,a0,a1",        2, "taken branch to word-aligned 32-bit target"),
 ("br_taken_half",   2, "beq a0,a0,1f\nc.nop\n1:\nadd t0,a0,a1\nc.nop", 3, "taken branch to halfword-aligned 32-bit target"),
 ("mul",             0, "mul t0,a0,a1",                               1, "MUL (low 32 bits)"),
 ("mulh",            0, "mulh t0,a0,a1",                              1, "MULH"),
 ("mulhu",           0, "mulhu t0,a0,a1",                             1, "MULHU"),
 ("mulhsu",          0, "mulhsu t0,a0,a1",                            1, "MULHSU"),
 ("mul_use",         0, "mul t0,a0,a1\nadd t1,t0,t0",                 2, "MUL, consumer immediately after"),
 ("div",             0, "div t0,a0,a1",                               1, "DIV"),
 ("divu",            0, "divu t0,a0,a1",                              1, "DIVU"),
 ("rem",             0, "rem t0,a0,a1",                               1, "REM"),
 ("remu",            0, "remu t0,a0,a1",                              1, "REMU"),
 ("div_by_zero",     0, "div t0,a0,zero",                             1, "DIV by zero"),
 ("div_use",         0, "div t0,a0,a1\nadd t1,t0,t0",                 2, "DIV, consumer immediately after"),
 ("rvc_alu",         1, "c.add a2,a1",                                1, "compressed ALU, dependent"),
 ("rvc_load",        1, "c.lw a2,0(s0)",                              1, "compressed load"),
 ("mix_16_32",       1, "c.add a2,a1\nadd a3,a0,a1",                  2, "alternating 16/32-bit instructions"),
 ("mix_16_32_32",    1, "c.add a2,a1\nadd a3,a0,a1\nadd a4,a0,a1",    3, "16-bit then two 32-bit instructions"),
]

def source(unit, rvc, k):
    body = "\n".join(unit for _ in range(k))
    mode = ".option rvc" if rvc else ".option norvc"
    return f""".section .text.init
.globl _start
_start:
  li s0, 0x4000
  li a0, 1000003
  li a1, 7
  li a2, 0
  li s1, {ITERS}
  .balign 4
loop:
  .option push
  {mode}
{body}
  .option pop
  addi s1,s1,-1
  bnez s1, loop
  li t4, 0x10000000
  li t5, 1
  sw t5, 0(t4)
1: j 1b
.section .data
.word 0
"""

def main():
    out = {}
    wd = os.path.join(ROOT, "build", "micro")
    for fast in (0, 1):
        v = build_sim(fast)
        res = {}
        for name, rvc, unit, nexec, desc in CASES:
            cyc = {}
            for k in (10, 30):
                src = os.path.join(wd, f"{name}_{k}.S")
                os.makedirs(wd, exist_ok=True)
                open(src, "w").write(source(unit, rvc, k))
                _, hexf = assemble(src, wd, f"{name}_{k}")
                d, _ = run(v, hexf)
                cyc[k] = d["cycles"]
            per_unit = (cyc[30] - cyc[10]) / (20 * ITERS)
            res[name] = dict(desc=desc, exec=nexec, cycles_per_unit=per_unit,
                             extra_per_unit=per_unit - nexec)
            print(f"FAST={fast} {name:16s} {per_unit:8.3f} cycles/unit  ({nexec} instr)  extra={per_unit-nexec:6.3f}")
        out[f"fast{fast}"] = res
    os.makedirs(os.path.join(ROOT, "tests", "perf", "results"), exist_ok=True)
    json.dump(out, open(os.path.join(ROOT, "tests", "perf", "results", "micro.json"), "w"), indent=1)

main()
