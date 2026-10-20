# Boot ROM (linked at 0x0004_0000, the reset vector of rv_soc): jump to the program in SRAM at 0x0.
.section .text.init
.globl _start
_start:
    li   t0, 0
    jr   t0
