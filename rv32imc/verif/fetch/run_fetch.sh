#!/bin/bash
# Block-level test of the fetch unit.  usage: verif/fetch/run_fetch.sh [+trace=1]   (run from the project root)
set -e
M=build/fetch_tb
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD --top-module tb_fetch \
  rtl/rv_pkg.sv rtl/rv_c_decoder.sv rtl/rv_npc.sv rtl/rv_fetch.sv tb/tb_fetch.sv --Mdir $M -o Vtb_fetch > $M.log 2>&1 || { grep -i error $M.log | head; exit 1; }
$M/Vtb_fetch "$@"
