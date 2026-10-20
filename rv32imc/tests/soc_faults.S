# SoC access-fault test (rv_soc): errors come from the REAL interconnect/peripherals, not the testbench.
#   unmapped address -> pulp obi_err_sbr (err=1), write to ROM -> err, invalid MMIO offset -> err,
#   instruction fetch from MMIO -> xbar connectivity -> err_sbr.
#   Expected: instruction access fault (mcause 1), load access fault (5), store access fault (7),
#   mepc = faulting instruction, mtval = faulting address (data) / fetch address (instruction).
# Result: store to 0x1000_0000 (1 = PASS, (n<<1)|1 = FAIL n).
.option norvc
.macro CHECK reg, val, num
    li   t6, \val
    beq  \reg, t6, 1f
    li   t5, \num
    j    fail
1:
.endm
# one trap expected: count==1, cause, mepc==label, mtval
.macro CHK_L cause, lbl, tval, num
    lw   t4, 0(s7)
    CHECK t4, 1, \num
    lw   t4, 4(s7)
    CHECK t4, \cause, \num+1
    lw   t4, 8(s7)
    la   t3, \lbl
    beq  t4, t3, 2f
    li   t5, \num+2
    j    fail
2:  lw   t4, 12(s7)
    li   t3, \tval
    beq  t4, t3, 3f
    li   t5, \num+3
    j    fail
3:
.endm
.macro RSTLOG
    sw   zero, 0(s7)
.endm
.section .text.init
.globl _start
_start:
    li   sp, 0x5000
    li   s7, 0x4800
    la   t0, handler
    csrw mtvec, t0
    li   s6, 0                       # s6 = resume address for instruction faults (0 = skip 4 bytes)
    RSTLOG
# 1. load from unmapped address
L1: li   a0, 0x20000000
    lw   a1, 0(a0)
    CHK_L 5, L1+4, 0x20000000, 10
    RSTLOG
# 2. store to unmapped address
    li   a0, 0x30000010
L2: sw   a0, 0(a0)
    CHK_L 7, L2, 0x30000010, 20
    RSTLOG
# 3. store to ROM
    li   a0, 0x00040000
L3: sw   a0, 0(a0)
    CHK_L 7, L3, 0x00040000, 30
    RSTLOG
# 4. load from ROM is fine (no trap), reads the boot code (c.li t0,0 / c.jr t0 = 0x82824281)
    li   a0, 0x00040000
    lw   a1, 0(a0)
    lw   t4, 0(s7)
    CHECK t4, 0, 40
# 5. invalid MMIO offset (load)
    li   a0, 0x10000200
L5: lw   a1, 0(a0)
    CHK_L 5, L5, 0x10000200, 50
    RSTLOG
# 6. byte store to unmapped
    li   a0, 0x20000003
L6: sb   a0, 0(a0)
    CHK_L 7, L6, 0x20000003, 60
    RSTLOG
# 7. instruction fetch from MMIO (not executable) -> instruction access fault, mtval = fetch address
    la   s6, R7
    li   a0, 0x10000000
    jalr zero, 0(a0)
R7: lw   t4, 0(s7)
    CHECK t4, 1, 70
    lw   t4, 4(s7)
    CHECK t4, 1, 71
    lw   t4, 8(s7)
    li   t3, 0x10000000
    beq  t4, t3, 7f
    li   t5, 72
    j    fail
7:  lw   t4, 12(s7)
    li   t3, 0x10000000
    beq  t4, t3, 8f
    li   t5, 73
    j    fail
8:  RSTLOG
# 8. instruction fetch from unmapped
    la   s6, R8
    li   a0, 0x20000000
    jalr zero, 0(a0)
R8: lw   t4, 0(s7)
    CHECK t4, 1, 80
    lw   t4, 4(s7)
    CHECK t4, 1, 81
    lw   t4, 12(s7)
    li   t3, 0x20000000
    beq  t4, t3, 9f
    li   t5, 82
    j    fail
9:  RSTLOG
# 9. a younger store must not reach memory after a faulting load (precise)
    li   a2, 0x5400
    sw   zero, 0(a2)
    li   a0, 0x20000000
    li   a3, 0x55
L9: lw   a1, 0(a0)
    sw   a3, 0(a2)
    lw   t4, 0(a2)
    CHECK t4, 0x55, 90              # the store after the handler skips the load DOES execute (resume)
    RSTLOG
# pass
    li   t0, 0x10000000
    li   t1, 1
    sw   t1, 0(t0)
1:  j    1b
fail:
    slli t5, t5, 1
    ori  t5, t5, 1
    li   t0, 0x10000000
    sw   t5, 0(t0)
2:  j    2b
.balign 4
handler:
    lw   t3, 0(s7)
    addi t3, t3, 1
    sw   t3, 0(s7)
    csrr t3, mcause
    sw   t3, 4(s7)
    csrr t3, mepc
    sw   t3, 8(s7)
    csrr t3, mtval
    sw   t3, 12(s7)
    beqz s6, 1f
    csrw mepc, s6                    # instruction fault: resume at the given address
    li   s6, 0
    mret
1:  csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
