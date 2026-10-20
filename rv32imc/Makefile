# Usage:
#   make sim                      # build Verilator model (FAST=0 DEPTH=4)
#   make run T=tests/directed     # assemble tests/directed.S and run it
#   make run T=tests/directed STALL=1 SEED=7 FAST=1
#   make regress                  # directed + random differential, all configs (predictor on and off)
#   make run T=... BP=0|1 GSHARE=0|1 BTBLOG=4 BHTLOG=6   # branch predictor options
RTL = rtl/rv_pkg.sv rtl/rv_c_decoder.sv rtl/rv_decoder.sv rtl/rv_alu.sv \
      rtl/rv_regfile.sv rtl/rv_csr.sv rtl/rv_mul.sv rtl/rv_div.sv rtl/rv_npc.sv rtl/rv_fetch.sv rtl/rv_core.sv
TB   = tb/tb_core.sv verif/obi_checker.sv
CROSS ?= riscv64-unknown-elf-
STALL ?= 0
SEED  ?= 1
# FAST=1 builds with FAST_REDIRECT=1; DEPTH = prefetch FIFO depth (power of two)
FAST  ?= 0
DEPTH ?= 4
# BP=1 enables the branch predictor (BTB/BHT/RAS); BP=0 = no prediction.
# GSHARE=1 indexes the BHT with global history.
BP    ?= 1
# OBIFATAL=1 stops the simulation at the first OBI protocol violation (verif/obi_checker.sv)
OBIFATAL ?= 1
GSHARE ?= 0
# ZICSR=1 includes the CSR file + machine-mode traps/interrupts; ZICSR=0 = plain RV32IMC (status pins only)
ZICSR ?= 1
# log2 of the BTB entries / BHT counters (defaults 4 and 6 = 16 entries and 64 counters; biRISC-V uses 32 and 512)
BTBLOG ?= 4
BHTLOG ?= 6
BUILD = build/f$(FAST)_d$(DEPTH)_b$(BP)_g$(GSHARE)$(if $(filter 0,$(ZICSR)),_nocsr,)$(if $(filter 0,$(OBIFATAL)),_nofatal,)$(if $(filter-out 4_6,$(BTBLOG)_$(BHTLOG)),_t$(BTBLOG)_$(BHTLOG),)

$(BUILD)/Vtb_core: $(RTL) $(TB)
	@mkdir -p build
	verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb_core \
	  -GFAST_REDIRECT=$(FAST) -GFETCH_DEPTH=$(DEPTH) -GBP_ENABLE=$(BP) -GZICSR=$(ZICSR) -GGSHARE=$(GSHARE) -GOBI_FATAL=$(OBIFATAL) \
	  -GBTB_N=$$((1<<$(BTBLOG))) -GBTB_W=$(BTBLOG) -GBHT_N=$$((1<<$(BHTLOG))) -GBHT_W=$(BHTLOG) \
	  --Mdir $(BUILD) -o Vtb_core $(RTL) $(TB) > $(BUILD).log 2>&1 || (cat $(BUILD).log; false)

sim: $(BUILD)/Vtb_core

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL --top-module rv_core $(RTL)

%.hex: %.S tests/link.ld
	$(CROSS)gcc -march=rv32imc_zicsr -mabi=ilp32 -nostdlib -nostartfiles -T $(if $(wildcard $*.ld),$*.ld,tests/link.ld) -o $*.elf $<
	$(CROSS)objcopy -O binary $*.elf $*.bin
	python3 tests/bin2hex.py $*.bin $@

run: $(BUILD)/Vtb_core $(T).hex
	$(BUILD)/Vtb_core +hex=$(T).hex +stall=$(STALL) +seed=$(SEED) $(if $(DUMP),+dump=$(DUMP),) $(if $(findstring access_faults,$(T)),+errram=1,)

regress:
	@for cfg in "0 4 1 0" "1 4 1 0" "0 2 1 0" "1 8 1 0" "0 4 0 0" "1 4 0 0" "0 4 1 1"; do set -- $$cfg; \
	  $(MAKE) -s sim FAST=$$1 DEPTH=$$2 BP=$$3 GSHARE=$$4 || exit 1; \
	  echo "== FAST_REDIRECT=$$1 FETCH_DEPTH=$$2 BP=$$3 GSHARE=$$4"; \
	  for t in directed traps access_faults; do for st in 0 1; do $(MAKE) -s run T=tests/$$t STALL=$$st FAST=$$1 DEPTH=$$2 BP=$$3 GSHARE=$$4 | grep "TB:" | sed "s/^/$$t stall=$$st /"; done; done; \
	  VTB=build/f$$1_d$$2_b$$3_g$$4/Vtb_core python3 tests/run_random.py 1 100 || exit 1; \
	done

# The three delivered variants: base (BP=0 ZICSR=0), bp (BP=1 ZICSR=0), zicsr (BP=1 ZICSR=1)
regress-variants:
	@for v in "base 0 0" "bp 1 0" "zicsr 1 1"; do set -- $$v; \
	  d=build/f0_d4_b$$2_g0$$( [ $$3 = 0 ] && echo _nocsr ); \
	  $(MAKE) -s sim BP=$$2 ZICSR=$$3 || exit 1; echo "== variant $$1 (BP=$$2 ZICSR=$$3)"; \
	  tl="directed"; [ $$3 = 1 ] && tl="directed traps access_faults"; \
	  for t in $$tl; do for st in 0 1; do $(MAKE) -s run T=tests/$$t STALL=$$st BP=$$2 ZICSR=$$3 | grep "TB:" | sed "s/^/$$t stall=$$st /"; done; done; \
	  VTB=$$d/Vtb_core python3 tests/run_random.py 1 300 || exit 1; \
	done
