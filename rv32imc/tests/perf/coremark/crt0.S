.section .text.init
.globl _start
_start:
    la   sp, _stack_top
    call main
    li   t4, 0x10000000
    li   t5, 1
    sw   t5, 0(t4)
1:  j    1b
