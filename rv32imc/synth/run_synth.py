#!/usr/bin/env python3
"""Area / logic-depth estimate: sv2v -> Yosys -> ABC mapped to an open standard-cell library.

Needs: sv2v (SV2V env var or on PATH), yosys, and a liberty file (LIB env var; the Nangate 45nm
typical-corner library from OpenROAD-flow-scripts was used for the report).
Everything is pre-layout: no wires, no clock tree, no placement. Use it to compare configurations.
Delay printed by ABC is combinational only (no clk->Q, no setup).
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SV2V = os.environ.get("SV2V", "sv2v")
LIB = os.environ["LIB"]
RTL = ["rv_pkg", "rv_c_decoder", "rv_decoder", "rv_alu", "rv_regfile", "rv_csr", "rv_mul", "rv_div", "rv_npc", "rv_fetch", "rv_core"]
TOP = "rv_core_syn"
# predictor configuration: SYN_BP=0 (none) / 1, SYN_BTB / SYN_BHT = log2 of the table sizes
BP = int(os.environ.get("SYN_BP", "1"))
BTB_LOG = int(os.environ.get("SYN_BTB", "4"))
BHT_LOG = int(os.environ.get("SYN_BHT", "6"))
BPSET = f"-set BP_ENABLE {BP} -set BTB_N {2**BTB_LOG} -set BTB_W {BTB_LOG} -set BHT_N {2**BHT_LOG} -set BHT_W {BHT_LOG}"
# ABC script: the default one plus buffering/sizing and a timing report (Yosys 0.33 prints none)
ABC = "+strash;&get,-n;&fraig,-x;&put;scorr;dc2;dretime;strash;&get,-n;&dch,-f;&nf,{D};&put;buffer;upsize,{D};dnsize,{D};topo;stime,-p"
WD = os.path.join(ROOT, "build", "synth"); os.makedirs(WD, exist_ok=True)

def convert():
    v = os.path.join(WD, "rv_core.v")
    with open(v, "w") as f:
        subprocess.check_call([SV2V, *[os.path.join(ROOT, "rtl", m + ".sv") for m in RTL], os.path.join(ROOT, "synth", "rv_core_syn.sv")], stdout=f)
    return v

def yosys(script, log):
    open(os.path.join(WD, log + ".ys"), "w").write(script)
    p = subprocess.run(["yosys", "-l", os.path.join(WD, log + ".log"), "-s", os.path.join(WD, log + ".ys")],
                       capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError(p.stdout[-2000:] + p.stderr[-2000:])
    return open(os.path.join(WD, log + ".log")).read()

def flow(v, fast, depth, flatten, period_ps):
    top = f"""read_verilog {v}
chparam -set FAST_REDIRECT {fast} -set FETCH_DEPTH {depth} {BPSET} {TOP}
hierarchy -check -top {TOP}
synth -top {TOP} {'-flatten' if flatten else ''}
opt -full
dfflibmap -liberty {LIB}
abc -liberty {LIB} -D {period_ps} -script {ABC}
opt_clean -purge
write_verilog -noattr {WD}/net_{fast}_{depth}_{int(flatten)}_{period_ps}.v
tee -o {WD}/stat_{fast}_{depth}_{int(flatten)}_{period_ps}.txt stat -liberty {LIB}
"""
    return yosys(top, f"y_{fast}_{depth}_{int(flatten)}_{period_ps}")

def parse(log):
    """Pull the last ABC stime summary and critical path out of the Yosys log."""
    lines = [l[5:] if l.startswith("ABC: ") else l for l in log.splitlines() if l.startswith("ABC: ")]
    area = delay = gates = None
    path = []
    for i, l in enumerate(lines):
        m = re.search(r"Gates\s*=\s*(\d+).*?Area\s*=\s*([\d.]+).*?Delay\s*=\s*([\d.]+)\s*ps", l)
        if m:
            gates, area, delay = int(m.group(1)), float(m.group(2)), float(m.group(3))
            path = []
        elif re.match(r"\s*Start-point|\s*End-point|\s*Path\s+\d+", l) or re.match(r"\s*\d+\s*:\s+\S+\s+\(\s*\d+", l):
            path.append(l.strip())
    return area, delay, gates, path

FLOP_OVERHEAD_PS = 200      # DFF_X1 clk->Q ~0.10 ns + setup 0.03-0.07 ns (typical corner), rounded up
NAND2_AREA = 0.798          # um^2, NAND2_X1 in the library, for gate-equivalents

def chip_area(stat_file, module):
    t = open(stat_file).read()
    m = re.search(r"Chip area for module '\\?" + re.escape(module) + r"': ([\d.]+)", t)
    return float(m.group(1)) if m else None

def module_areas(stat_file):
    """Area per module from the hierarchical stat report (module headers are '=== name ===')."""
    out, cur = {}, None
    for line in open(stat_file):
        h = re.match(r"=== (.*) ===", line.strip())
        if h:
            cur = h.group(1)
            cur = "rv_core" if cur.endswith("rv_core") else ("rv_fetch" if "rv_fetch" in cur else ("rv_npc" if "rv_npc" in cur else cur))
            continue
        m = re.match(r"\s*Chip area for module .*: ([\d.]+)\s*$", line)
        if m and cur:
            out[cur] = float(m.group(1))
    return out

def main():
    v = convert()
    out = {}
    # the FAST_REDIRECT=1 flow crashes Yosys 0.33's SHARE pass once the predictor is in; SYN_FAST=0 skips it
    for fast in [int(x) for x in os.environ.get("SYN_FAST", "0,1").split(",")]:
        for period, tag in ((1, "speed"), (4000, "area")):
            log = flow(v, fast, 4, True, period)
            area, delay, gates, path = parse(log)
            total = chip_area(f"{WD}/stat_{fast}_4_1_{period}.txt", TOP)
            out[f"flat_fast{fast}_{tag}"] = dict(
                comb_area_um2=area, logic_delay_ps=delay, comb_gates=gates, path_gates=sum(1 for p in path if p.startswith("Path")),
                total_area_um2=total, nand2_gate_equiv=total / NAND2_AREA,
                cycle_ps=delay + FLOP_OVERHEAD_PS, fmax_mhz=1e6 / (delay + FLOP_OVERHEAD_PS))
            d = out[f"flat_fast{fast}_{tag}"]
            print(f"flat FAST={fast} {tag:5s}: total={total:.0f} um2 ({d['nand2_gate_equiv']/1000:.1f} kGE) "
                  f"logic={delay:.0f} ps  cycle~{d['cycle_ps']:.0f} ps  fmax~{d['fmax_mhz']:.0f} MHz", flush=True)
    flow(v, 0, 4, False, 4000)
    out["modules_um2"] = module_areas(f"{WD}/stat_0_4_0_4000.txt")
    print("modules:", out["modules_um2"])
    # experiment: blackbox the multiplier and divider to expose the next-worst path
    script = open(f"{WD}/y_0_4_1_1.ys").read().replace("synth -top rv_core_syn -flatten",
              "blackbox rv_mul rv_div\nsynth -top rv_core_syn -flatten")
    script = "\n".join(l for l in script.splitlines() if not l.startswith(("tee ", "write_verilog")))
    log = yosys(script, "y_nomuldiv")
    area, delay, gates, path = parse(log)
    out["flat_fast0_speed_no_muldiv"] = dict(logic_delay_ps=delay, cycle_ps=delay + FLOP_OVERHEAD_PS,
                                             fmax_mhz=1e6 / (delay + FLOP_OVERHEAD_PS))
    print(f"no mul/div: logic={delay:.0f} ps fmax~{out['flat_fast0_speed_no_muldiv']['fmax_mhz']:.0f} MHz")
    out["config"] = dict(BP=BP, BTB=2**BTB_LOG, BHT=2**BHT_LOG)
    json.dump(out, open(os.path.join(ROOT, "tests/perf/results", "synth.json" if not BP else f"synth_bp_btb{2**BTB_LOG}_bht{2**BHT_LOG}.json"), "w"), indent=1)
main()
