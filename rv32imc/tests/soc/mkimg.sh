#!/bin/bash
# Rebuild the SoC boot ROM image and the SoC fault-test image into build/socimg (run from anywhere).
set -e
cd "$(dirname "$0")/../.."
X=${CROSS:-riscv64-unknown-elf-}; O=build/socimg; mkdir -p $O
F="-march=rv32imc_zicsr -mabi=ilp32 -nostdlib -nostartfiles"
$X"gcc" $F -T tests/soc/rom.ld tests/soc/boot.S -o $O/boot.elf
$X"gcc" $F -T tests/link.ld tests/soc_faults.S -o $O/soc_faults.elf
for n in boot soc_faults; do $X"objcopy" -O binary $O/$n.elf $O/$n.bin; python3 tests/bin2hex.py $O/$n.bin $O/$n.hex; done
