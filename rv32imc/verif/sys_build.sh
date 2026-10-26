#!/bin/bash
# usage: verif/sys_build.sh <mdir> [-G... verilator args]    (project root)  builds tb_sys = core + separate imem/dmem
M=$1; shift
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD --top-module tb_sys \
  rtl/rv_pkg.sv rtl/rv_c_decoder.sv rtl/rv_decoder.sv rtl/rv_alu.sv rtl/rv_regfile.sv rtl/rv_csr.sv rtl/rv_mul.sv rtl/rv_div.sv \
  rtl/rv_npc.sv rtl/rv_fetch.sv rtl/rv_core.sv rtl/mem/rv_bram_tdp.sv rtl/mem/rv_obi_ram_port.sv rtl/mem/rv_obi_imem.sv \
  rtl/mem/rv_obi_dmem.sv rtl/mem/rv_obi_err.sv rtl/mem/rv_obi_mmio.sv rtl/mem/rv32imc_sys.sv verif/obi_checker.sv tb/tb_sys.sv \
  "$@" --Mdir $M -o Vtb_sys > $M.log 2>&1 || { grep -i "error" $M.log | head; exit 1; }
