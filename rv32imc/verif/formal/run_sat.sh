#!/bin/bash
# usage: verif/formal/run_sat.sh <tag> <depth> [PARAM=VAL ...]     (run from the project root; needs sv2v, yosys)
# Bounded proof with Yosys' built-in SAT (sat -seq N -prove-asserts) of verif/formal/rv_obi_formal.sv on rv_core.
# Why not sby: the sby/Yosys pair installed here (sby newer than Yosys 0.33) silently drops the assertions in its
# AIGER flow, and its Boolector (1.5) / z3 SMT flows die or hang on this design.  Plain `sat` sees all assertions.
# Initial state: reset flops reset by the harness' first-cycle reset; every other flop starts ARBITRARY (over-approximation).
tag=$1; depth=$2; shift 2
W=build/formal/$tag; mkdir -p $W
${SV2V:-sv2v} rtl/rv_pkg.sv rtl/rv_c_decoder.sv rtl/rv_decoder.sv rtl/rv_alu.sv rtl/rv_regfile.sv rtl/rv_csr.sv rtl/rv_mul.sv rtl/rv_div.sv \
  rtl/rv_npc.sv rtl/rv_fetch.sv rtl/rv_core.sv > $W/flat.v 2> $W/sv2v.err || { cat $W/sv2v.err; exit 1; }
{ echo "read_verilog -formal -sv $W/flat.v verif/formal/rv_obi_formal.sv"
  for a in "$@"; do echo "chparam -set ${a%=*} ${a#*=} rv_obi_formal"; done
  echo "prep -top rv_obi_formal"; echo "flatten"; echo "memory_map"; echo "async2sync"; echo "dffunmap"; echo "opt -fast"
  echo "sat -seq $depth -prove-asserts -set-assumes -verify -timeout ${TIMEOUT:-1200} rv_obi_formal"; } > $W/run.ys
if yosys -q -l $W/log.txt $W/run.ys >/dev/null 2>&1; then echo "[$tag depth=$depth $*] PROVED (no assertion can fail within $depth cycles from reset)";
else echo "[$tag depth=$depth $*] FAILED or ERROR -> $W/log.txt"; grep -m1 "ERROR" $W/log.txt; fi
