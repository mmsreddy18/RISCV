#!/usr/bin/env python3
"""Structural check of OBI R-21.1: does any manager output depend COMBINATIONALLY on a link input?
Method: Yosys elaborates + flattens rv_core (parameters from argv), the JSON netlist is walked backwards from
each output bit through combinational cells only; flip-flop (and latch) cells end the walk (their Q is a
register boundary).  Memory read ports (regfile) are treated as combinational (conservative).
usage: comb_deps.py <core.v> [PARAM=VAL ...]"""
import json, subprocess, sys, os, tempfile, collections
src = sys.argv[1]; params = sys.argv[2:]
tmp = tempfile.mkdtemp()
ys = os.path.join(tmp, "s.ys"); js = os.path.join(tmp, "n.json")
cp = "".join(f"chparam -set {p.split('=')[0]} {p.split('=')[1]} rv_core\n" for p in params)
open(ys, "w").write(f"read_verilog -sv {src}\n{cp}hierarchy -top rv_core\nproc\nflatten\nopt_clean\nwrite_json {js}\n")
subprocess.run(["yosys", "-q", ys], check=True, stdout=subprocess.DEVNULL)
mod = json.load(open(js))["modules"]["rv_core"]
ports = mod["ports"]
drv = {}                                   # bit -> (cell name)
for cn, c in mod["cells"].items():
    for pn, bits in c["connections"].items():
        if c["port_directions"][pn] == "output":
            for b in bits:
                if isinstance(b, int): drv[b] = cn
def is_seq(t): return "dff" in t or "dlatch" in t or t in ("$sr", "$adlatch")
def cone_inputs(out_bits):
    seen, stack, hit = set(), list(out_bits), set()
    inbit = {}
    for pn, p in ports.items():
        if p["direction"] == "input":
            for i, b in enumerate(p["bits"]): inbit[b] = pn
    while stack:
        b = stack.pop()
        if b in seen or not isinstance(b, int): continue
        seen.add(b)
        if b in inbit: hit.add(inbit[b]); continue
        cn = drv.get(b)
        if cn is None: continue
        c = mod["cells"][cn]
        if is_seq(c["type"]): continue
        for pn, bits in c["connections"].items():
            if c["port_directions"][pn] == "input": stack.extend(bits)
    return hit
for o in ["instr_req_o", "instr_addr_o", "data_req_o", "data_addr_o", "data_we_o", "data_be_o", "data_wdata_o"]:
    deps = sorted(cone_inputs(ports[o]["bits"]))
    link = [d for d in deps if d.startswith(("instr_gnt", "instr_rvalid", "instr_err", "instr_rdata", "data_gnt", "data_rvalid", "data_err", "data_rdata"))]
    print(f"{o:14s} <- link inputs: {', '.join(link) if link else '(none)'}   [other: {', '.join(d for d in deps if d not in link) or '-'}]")
