#!/usr/bin/env python3
"""Branch-predictor size sweep: builds tb_core for each configuration (Verilator) and runs CoreMark.
usage: bp_sweep.py [coremark.hex]   (project root; writes build/sw/results.csv and prints a table)"""
import subprocess, sys, os, re, csv
from concurrent.futures import ThreadPoolExecutor
hexf = sys.argv[1] if len(sys.argv) > 1 else "build/cm/O2_rvc/coremark.hex"
SRC = "rtl/rv_pkg.sv rtl/rv_c_decoder.sv rtl/rv_decoder.sv rtl/rv_alu.sv rtl/rv_regfile.sv rtl/rv_csr.sv rtl/rv_mul.sv rtl/rv_div.sv rtl/rv_npc.sv rtl/rv_fetch.sv rtl/rv_core.sv tb/tb_core.sv verif/obi_checker.sv".split()
def cfg(name, bp=1, btb=4, bht=6, ras=3, gs=0): return dict(name=name, bp=bp, btbw=btb, bhtw=bht, rasw=ras, gs=gs)
C = [cfg("no predictor", bp=0)]
C += [cfg(f"BTB 2^{w}", btb=w) for w in (1, 2, 3, 4, 5)]
C += [cfg(f"BHT 2^{w}", bht=w) for w in (2, 4, 6, 8)]
C += [cfg(f"RAS 2^{w}", ras=w) for w in (1, 2, 3, 4)]
C += [cfg("gshare, BHT 2^6", gs=1), cfg("gshare, BHT 2^8", bht=8, gs=1)]
C += [cfg("small: BTB 2^1 BHT 2^2 RAS 2^1", btb=1, bht=2, ras=1), cfg("small: BTB 2^2 BHT 2^4 RAS 2^2", btb=2, bht=4, ras=2),
      cfg("mid: BTB 2^3 BHT 2^5 RAS 2^2", btb=3, bht=5, ras=2)]
if os.environ.get("SWEEP") == "combo":      # second round: combinations around the knee of the first sweep
    C = [cfg("no predictor", bp=0), cfg("default 16/64/8", btb=4, bht=6, ras=3)]
    C += [cfg(f"BTB {1<<b} BHT {1<<h} RAS {1<<r}", btb=b, bht=h, ras=r) for b, h, r in
          ((4, 4, 1), (4, 4, 2), (3, 4, 1), (3, 4, 2), (3, 3, 1), (2, 4, 1), (5, 4, 1), (5, 5, 1), (4, 5, 1))]
def run(c):
    d = "build/sw/" + re.sub(r"\W+", "_", c["name"])
    g = [f"-GBP_ENABLE={c['bp']}", "-GZICSR=1", f"-GGSHARE={c['gs']}", "-GOBI_FATAL=0", f"-GBTB_N={1<<c['btbw']}", f"-GBTB_W={c['btbw']}",
         f"-GBHT_N={1<<c['bhtw']}", f"-GBHT_W={c['bhtw']}", f"-GRAS_N={1<<c['rasw']}", f"-GRAS_W={c['rasw']}"]
    r = subprocess.run(["verilator", "--binary", "--timing", "-Wno-fatal", "-Wno-lint", "-Wno-style", "-Wno-TIMESCALEMOD", "--top-module", "tb_core",
                        *g, "--Mdir", d, "-o", "V", *SRC], capture_output=True, text=True)
    if r.returncode: return dict(c, err="build failed: " + r.stderr[-200:])
    o = subprocess.run([d + "/V", f"+hex={hexf}", "+maxcyc=40000000", "+perf=1"], capture_output=True, text=True).stdout
    m = re.search(r"PERFROI cycles=(\d+) issued=(\d+) fetch=(\d+) branch=(\d+)", o)
    ok = "TB: PASS" in o
    if not m: return dict(c, err="no PERFROI line")
    cyc, iss, fe, br = map(int, m.groups())
    return dict(c, cycles=cyc, issued=iss, cpi=cyc / iss, branch_stall=br, passed=ok, err="")
os.makedirs("build/sw", exist_ok=True)
with ThreadPoolExecutor(2) as ex: R = list(ex.map(run, C))
base = next(r for r in R if r["name"] == "no predictor")["cycles"]
with open("build/sw/results.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["config", "BTB", "BHT", "RAS", "gshare", "cycles", "CPI", "branch_stall_cycles", "speedup_vs_none", "pass"])
    for r in R:
        if r.get("err"): print(r["name"], r["err"]); continue
        w.writerow([r["name"], 1 << r["btbw"] if r["bp"] else 0, 1 << r["bhtw"] if r["bp"] else 0, 1 << r["rasw"] if r["bp"] else 0, r["gs"],
                    r["cycles"], f"{r['cpi']:.3f}", r["branch_stall"], f"{base / r['cycles']:.3f}", r["passed"]])
print(f"{'configuration':34s} {'cycles':>9s} {'CPI':>6s} {'br-stall':>9s} {'speedup':>8s}  pass")
for r in R:
    if r.get("err"): continue
    print(f"{r['name']:34s} {r['cycles']:9d} {r['cpi']:6.3f} {r['branch_stall']:9d} {base/r['cycles']:8.3f}  {r['passed']}")
