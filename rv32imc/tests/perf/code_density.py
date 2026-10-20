#!/usr/bin/env python3
"""Code-only size (.text* of the object files, rodata excluded): rv32im vs rv32imc builds of the same C."""
import glob, json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
from common import *

def text_bytes(objs):
    total = 0
    for o in objs:
        out = subprocess.check_output([CROSS + "size", "-A", o], text=True)
        for line in out.splitlines():
            parts = line.split()
            if parts and parts[0].startswith(".text"):
                total += int(parts[1])
    return total

def main():
    res = {}
    # CoreMark / Dhrystone objects built earlier by the run scripts
    for name, tags, pat in (("CoreMark -O2", ("O2_rvc", "O2_norvc"), "build/cm/{}/core_*.o"),
                            ("CoreMark -O3 unrolled", ("O3u_rvc", "O3u_norvc"), "build/cm/{}/core_*.o"),
                            ("Dhrystone -O2", ("O2_wordstr", "O2_wordstr_norvc"), "build/dhry/{}/dhry*.o")):
        c = text_bytes(glob.glob(os.path.join(ROOT, pat.format(tags[0]))))
        n = text_bytes(glob.glob(os.path.join(ROOT, pat.format(tags[1]))))
        res[name] = dict(rvc=c, norvc=n)
    # kernels
    wd = os.path.join(ROOT, "build", "kern_den"); os.makedirs(wd, exist_ok=True)
    kc = kn = 0
    for k in range(1, 10):
        sizes = {}
        for march in ("rv32imc", "rv32im"):
            o = os.path.join(wd, f"k{k}_{march}.o")
            subprocess.check_call([CROSS + "gcc", f"-march={march}", "-mabi=ilp32", "-ffreestanding", "-nostdlib", "-O2",
                                   "-fno-tree-loop-distribute-patterns", f"-DK={k}", "-c",
                                   os.path.join(ROOT, "tests/perf/kernels/kernels.c"), "-o", o])
            sizes[march] = text_bytes([o])
        kc += sizes["rv32imc"]; kn += sizes["rv32im"]
    res["Kernel suite (9 kernels, -O2)"] = dict(rvc=kc, norvc=kn)
    for k, v in res.items():
        v["saving_pct"] = 100.0 * (v["norvc"] - v["rvc"]) / v["norvc"]
        print(f"{k:32s} rv32im={v['norvc']:6d} rv32imc={v['rvc']:6d} saving={v['saving_pct']:.1f}%")
    json.dump(res, open(os.path.join(ROOT, "tests/perf/results/code_density.json"), "w"), indent=1)
main()
