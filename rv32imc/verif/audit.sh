#!/bin/bash
# usage: verif/audit.sh <tag>   -> verif/results/audit_<tag>.txt : OBI violations per program / FAST / stall
tag=$1; out=verif/results/audit_$tag.txt; : > $out
for fast in 0 1; do
  make -s sim FAST=$fast OBIFATAL=0 >/dev/null 2>&1
  d=build/f${fast}_d4_b1_g0_nofatal
  for prog in tests/directed.hex tests/traps.hex build/cm/O2_rvc/coremark.hex; do
    for st in 0 1; do
      extra=""; [ "$prog" = build/cm/O2_rvc/coremark.hex ] && [ $st = 1 ] && continue
      r=$($d/Vtb_core +hex=$prog +stall=$st +seed=3 +maxcyc=40000000 2>&1)
      res=$(echo "$r" | grep -o "TB: [A-Z]*" | head -1)
      v=$(echo "$r" | awk '/summary/{p=$1} /violation\(s\)/{ if ($2+0>0) printf "%s %s=%s; ", p, $1, $2 }')
      echo "FAST=$fast stall=$st $(basename $prog .hex): $res  violations: ${v:-none}" | tee -a $out
    done
  done
done
