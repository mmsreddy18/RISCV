#!/bin/bash
# usage: verif/formal/run_formal.sh <tag> <depth> <full engine line, e.g. "abc bmc3" or "smtbmc z3"> [PARAM=VAL ...]   (project root; needs sv2v, sby, yosys, boolector/z3)
tag=$1; depth=$2; eng=$3; shift 3
W=build/formal/$tag; mkdir -p $W
${SV2V:-sv2v} rtl/rv_pkg.sv rtl/rv_c_decoder.sv rtl/rv_decoder.sv rtl/rv_alu.sv rtl/rv_regfile.sv rtl/rv_csr.sv rtl/rv_mul.sv rtl/rv_div.sv \
  rtl/rv_npc.sv rtl/rv_fetch.sv rtl/rv_core.sv > $W/flat.v 2> $W/sv2v.err || { cat $W/sv2v.err; exit 1; }
P=""; for a in "$@"; do P="$P
chparam -set ${a%=*} ${a#*=} rv_obi_formal"; done
cat > $W/f.sby <<EOT
[tasks]
bmc
prove

[options]
bmc: mode bmc
prove: mode prove
depth $depth
multiclock off

[engines]
$eng

[script]
read_verilog -formal -sv flat.v
read_verilog -formal -sv rv_obi_formal.sv$P
prep -top rv_obi_formal

[files]
$PWD/$W/flat.v
$PWD/verif/formal/rv_obi_formal.sv
EOT
sby -f -d $W/out $W/f.sby ${MODE:-bmc} 2>&1 | tail -${TAIL:-8}
