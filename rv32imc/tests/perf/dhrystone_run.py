#!/usr/bin/env python3
"""Build Dhrystone (riscv-tests sources) in several configurations and run on the RTL."""
import json, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
from common import *

RUNS = 500           # NUMBER_OF_RUNS in the upstream header
VAX_MIPS = 1757      # Dhrystones/s of a VAX 11/780 (1 DMIPS)
BUILDS = [  # tag, march, flags, fast-string-functions
 ("O2_bytestr",   "rv32imc", "-O2", 0),
 ("O2_wordstr",   "rv32imc", "-O2", 1),
 ("O3_wordstr",   "rv32imc", "-O3", 1),
 ("O2_wordstr_norvc", "rv32im", "-O2", 1),
]

def check_values(out):
    """Compare each 'name: value / should be: expected' pair Dhrystone prints."""
    lines = out.splitlines()
    bad = []
    n = 0
    for i, l in enumerate(lines):
        if l.strip().startswith("should be:") and i > 0:
            exp = l.split("should be:")[1].strip()
            name, _, val = lines[i - 1].partition(":")
            val = val.strip()
            if "implementation" in exp:
                continue
            if exp == "Number_Of_Runs + 10":
                exp = str(RUNS + 10)
            n += 1
            if val != exp:
                bad.append((name.strip(), val, exp))
    return n, bad

def main():
    res = {}
    sims = {f: build_sim(f) for f in (0, 1)}
    for tag, march, flags, fast in BUILDS:
        out = os.path.join(ROOT, "build", "dhry", tag)
        env = dict(os.environ)
        if fast: env["FAST_STR"] = "1"
        else: env.pop("FAST_STR", None)
        sz = subprocess.check_output([os.path.join(ROOT, "tests/perf/dhrystone/build_dhrystone.sh"), out, march, *flags.split()],
                                     env=env, text=True)
        res[tag] = dict(march=march, flags=flags, fast_str=fast, text_bytes=int(sz.strip().splitlines()[-1].split()[0]))
        for f in (0, 1):
            d, o = run(sims[f], os.path.join(out, "dhry.hex"), maxcyc=50_000_000)
            n, bad = check_values(o)
            d["values_checked"] = n; d["values_bad"] = len(bad)
            d["dmips_per_mhz"] = (RUNS / d["cycles"]) * 1e6 / VAX_MIPS
            d["cycles_per_run"] = d["cycles"] / RUNS
            d["instr_per_run"] = d["issued"] / RUNS
            d["cpi"] = d["cycles"] / d["issued"]
            res[tag][f"fast{f}"] = d
            print(f"{tag:18s} FAST={f} cycles/run={d['cycles_per_run']:7.1f} instr/run={d['instr_per_run']:6.1f} "
                  f"CPI={d['cpi']:.3f} DMIPS/MHz={d['dmips_per_mhz']:.3f} checked={n} bad={len(bad)} {bad[:2] if bad else ''}")
    json.dump(res, open(os.path.join(ROOT, "tests/perf/results/dhrystone.json"), "w"), indent=1)
main()
