#!/usr/bin/env python3
"""Run the kernel suite on the RTL (both fetch modes) and compare checksums with a host build."""
import json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
from common import *

KERNELS = [(1, "matmul 16x16"), (2, "bubble sort 128"), (3, "crc32 1 KiB"), (4, "word copy 4x2 KiB"),
           (5, "fir 32 taps x 256"), (6, "list walk 5120 nodes"), (7, "gcd (div/rem) x200"),
           (8, "sieve 2048"), (9, "fib(18) recursive")]
PERF = os.path.join(ROOT, "tests", "perf")

def main():
    res = {}
    sims = {f: build_sim(f) for f in (0, 1)}
    wd = os.path.join(ROOT, "build", "kern"); os.makedirs(wd, exist_ok=True)
    libc = os.path.join(wd, "libc_min.o"); crt = os.path.join(wd, "crt0.o")
    common = ["-march=rv32imc", "-mabi=ilp32", "-ffreestanding", "-nostdlib"]
    subprocess.check_call([CROSS + "gcc", *common, "-O2", "-fno-tree-loop-distribute-patterns", "-c", f"{PERF}/coremark/libc_min.c", "-o", libc])
    subprocess.check_call([CROSS + "gcc", *common, "-c", f"{PERF}/coremark/crt0.S", "-o", crt])
    for kid, name in KERNELS:
        host = os.path.join(wd, f"host{kid}")
        subprocess.check_call(["gcc", "-O1", f"-DK={kid}", "-DHOST", f"{PERF}/kernels/kernels.c", "-o", host])
        expect = subprocess.check_output([host], text=True).strip()
        obj = os.path.join(wd, f"k{kid}.o"); elf = os.path.join(wd, f"k{kid}.elf")
        subprocess.check_call([CROSS + "gcc", *common, "-O2", "-fno-tree-loop-distribute-patterns", f"-DK={kid}", "-c", f"{PERF}/kernels/kernels.c", "-o", obj])
        subprocess.check_call([CROSS + "gcc", *common, "-T", f"{PERF}/coremark/bench.ld", "-o", elf, crt, obj, libc, "-lgcc"])
        subprocess.check_call([CROSS + "objcopy", "-O", "binary", elf, elf + ".bin"])
        subprocess.check_call(["python3", f"{ROOT}/tests/bin2hex.py", elf + ".bin", elf + ".hex"])
        res[name] = {}
        for f in (0, 1):
            d, o = run(sims[f], elf + ".hex", maxcyc=50_000_000)
            ok = o.splitlines()[0].strip() == expect if o.strip() else False
            d["checksum_ok"] = ok; d["cpi"] = d["cycles"] / d["issued"]
            res[name][f"fast{f}"] = d
            st = {k: d[k] for k in ("fetch", "branch", "loaduse", "exmul", "exdiv", "exmem", "wbstall")}
            print(f"{name:22s} FAST={f} cycles={d['cycles']:8d} instr={d['issued']:8d} CPI={d['cpi']:.3f} ok={ok} "
                  + " ".join(f"{k}={v/d['cycles']*100:4.1f}%" for k, v in st.items() if v))
    json.dump(res, open(os.path.join(PERF, "results", "kernels.json"), "w"), indent=1)
main()
