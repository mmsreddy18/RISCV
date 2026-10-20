#!/bin/bash
# usage: verif/soc_build.sh <mdir> [-G... verilator args]   (run from the project root; needs verif/third_party/fetch.sh first)
M=$1; shift
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD --top-module tb_soc -f verif/soc.f \
  rtl/rv_pkg.sv rtl/rv_c_decoder.sv rtl/rv_decoder.sv rtl/rv_alu.sv rtl/rv_regfile.sv rtl/rv_csr.sv rtl/rv_mul.sv rtl/rv_div.sv \
  rtl/rv_npc.sv rtl/rv_fetch.sv rtl/rv_core.sv rtl/soc/rv_obi_rom.sv rtl/soc/rv_obi_mmio.sv rtl/soc/rv_sram_array.sv rtl/soc/rv_obi_mem.sv rtl/soc/rv_soc.sv \
  tb/tb_soc.sv "$@" --Mdir $M -o Vtb_soc > $M.log 2>&1 || { grep -i error $M.log | head; exit 1; }
