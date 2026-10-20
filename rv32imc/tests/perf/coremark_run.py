#!/usr/bin/env python3
"""Build CoreMark in several configurations and run it on the RTL (both fetch modes)."""
import json, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
from common import *

ITER = 10
BUILDS = [  # tag, march, flags
 ("O2_rvc",     "rv32imc", "-O2"),
 ("O2_norvc",   "rv32im",  "-O2"),
 ("O3u_rvc",    "rv32imc", "-O3 -funroll-all-loops -finline-limit=200"),
 ("O3u_norvc",  "rv32im",  "-O3 -funroll-all-loops -finline-limit=200"),
 ("Os_rvc",     "rv32imc", "-Os"),
]
KNOWN = ["0xe9f5", "0xe714", "0x1fd7", "0x8e3a", "0xfcaf"]   # seedcrc, list, matrix, state, final (10 iterations)

def main():
    res = {}
    sims = {f: build_sim(f) for f in (0, 1)}
    for tag, march, flags in BUILDS:
        out = os.path.join(ROOT, "build", "cm", tag)
        env = dict(os.environ, ITERATIONS=str(ITER))
        sz = subprocess.check_output([os.path.join(ROOT, "tests/perf/coremark/build_coremark.sh"), out, march, *flags.split()],
                                     env=env, text=True)
        text = int(sz.strip().splitlines()[-1].split()[0])
        res[tag] = dict(march=march, flags=flags, text_bytes=text)
        for f in (0, 1):
            d, o = run(sims[f], os.path.join(out, "coremark.hex"), maxcyc=400_000_000)
            ok = "Correct operation validated" in o and all(k in o for k in KNOWN)
            d["validated"] = ok
            d["coremark_per_mhz"] = ITER * 1e6 / d["cycles"]
            d["cpi"] = d["cycles"] / d["issued"]
            res[tag][f"fast{f}"] = d
            print(f"{tag:11s} FAST={f} text={text:6d} cycles={d['cycles']:9d} instr={d['issued']:9d} "
                  f"CPI={d['cpi']:.3f} CoreMark/MHz={d['coremark_per_mhz']:.3f} valid={ok}")
    os.makedirs(os.path.join(ROOT, "tests/perf/results"), exist_ok=True)
    json.dump(res, open(os.path.join(ROOT, "tests/perf/results/coremark.json"), "w"), indent=1)
main()
