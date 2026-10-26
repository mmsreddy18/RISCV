.section .text.init
.globl _start
_start:
    la   sp, _stack_top
    call main
    # a0 = 0 -> PASS (tohost=1), else (code<<1)|1
    beqz a0, 2f
    slli a0, a0, 1
    ori  a0, a0, 1
    j    3f
2:  li   a0, 1
3:  li   t4, 0x10000000
    sw   a0, 0(t4)
1:  j    1b
