# Directed self-checking test: OBI err responses -> access-fault exceptions.
#   instruction access fault (mcause 1), load access fault (5), store access fault (7)
# Result: store to 0x1000_0000 (1 = PASS, (n<<1)|1 = FAIL test n).
# Error addresses (testbench): 0x2000_0000..0x2FFF_FFFF and RAM 0x0003_C000..0x0003_FFFF.
# Registers: s7 = log base (0x4800), s2 = marker word (0x5400); s8..s11 = handler temporaries.
#   log: +0 count  +4 cause  +8 mepc  +12 mtval  +20 resume address (instruction faults)
#        +24 marker-word value seen at trap entry (checks that younger stores had not issued)

.equ HANDLER_INSTRS, 22     # instructions the handler executes for a 4-byte load fault (counted below)

.macro CHECK reg, val, num
    li   t6, \val
    beq  \reg, t6, 1f
    li   t5, \num
    j    fail
1:
.endm
.macro CHECKR r1, r2, num
    beq  \r1, \r2, 1f
    li   t5, \num
    j    fail
1:
.endm
.macro RSTLOG
    sw   zero, 0(s7)
.endm
# count, cause, mepc (label), mtval (value)
.macro CHK_L cnt, cause, lbl, tval, num
    lw   t4, 0(s7)
    CHECK t4, \cnt, \num
    lw   t4, 4(s7)
    CHECK t4, \cause, \num+1
    lw   t4, 8(s7)
    la   t3, \lbl
    CHECKR t4, t3, \num+2
    lw   t4, 12(s7)
    li   t3, \tval
    CHECKR t4, t3, \num+3
.endm
# count, cause, mepc (value), mtval (value)
.macro CHK_V cnt, cause, mepc, tval, num
    lw   t4, 0(s7)
    CHECK t4, \cnt, \num
    lw   t4, 4(s7)
    CHECK t4, \cause, \num+1
    lw   t4, 8(s7)
    li   t3, \mepc
    CHECKR t4, t3, \num+2
    lw   t4, 12(s7)
    li   t3, \tval
    CHECKR t4, t3, \num+3
.endm

.section .text.init
.globl _start
_start:
    li   sp, 0x5000
    li   s7, 0x4800
    li   s2, 0x5400
    sw   zero, 0(s2)
    la   t0, handler
    csrw mtvec, t0
    sw   zero, 0(s7)
    li   s1, 0x20000100              # error address (aligned)

# ---- 1. load word: cause 5, mepc, mtval = address, rd NOT written
    li   a2, 0x1234
    RSTLOG
l1: lw   a2, 0(s1)
    CHK_L 1, 5, l1, 0x20000100, 1
    CHECK a2, 0x1234, 5

# ---- 2. other load widths (mtval is the effective address)
    RSTLOG
l2a: lb   a2, 3(s1)
    CHK_L 1, 5, l2a, 0x20000103, 6
    RSTLOG
l2b: lbu  a2, 1(s1)
    CHK_L 1, 5, l2b, 0x20000101, 10
    RSTLOG
l2c: lh   a2, 2(s1)
    CHK_L 1, 5, l2c, 0x20000102, 14
    RSTLOG
l2d: lhu  a2, 0(s1)
    CHK_L 1, 5, l2d, 0x20000100, 18
    CHECK a2, 0x1234, 22

# ---- 3. stores: cause 7
    RSTLOG
l3a: sw   a2, 0(s1)
    CHK_L 1, 7, l3a, 0x20000100, 23
    RSTLOG
l3b: sh   a2, 2(s1)
    CHK_L 1, 7, l3b, 0x20000102, 27
    RSTLOG
l3c: sb   a2, 1(s1)
    CHK_L 1, 7, l3c, 0x20000101, 31

# ---- 4. precision: a younger store must not have reached memory when the trap is taken
    li   s3, 0x77
    li   a4, 0
    RSTLOG
l4: lw   a2, 0(s1)
    sw   s3, 0(s2)                   # younger store: executed once, AFTER the handler
    addi a4, a4, 1                   # younger ALU op: executed once
    CHK_L 1, 5, l4, 0x20000100, 35
    lw   t4, 24(s7)
    CHECK t4, 0, 39                  # marker was still 0 at trap entry
    lw   t4, 0(s2)
    CHECK t4, 0x77, 40               # ... and the store did happen afterwards
    CHECK a4, 1, 41

# ---- 5. consumer directly behind the faulting load sees the OLD register value
    li   a2, 0x1234
    RSTLOG
l5: lw   a2, 0(s1)
    add  a3, a2, a2
    CHK_L 1, 5, l5, 0x20000100, 42
    CHECK a3, 0x2468, 46

# ---- 6. two faulting accesses in a row, then a good access
    la   s4, good
    RSTLOG
l6a: lw  a2, 0(s1)
l6b: sw  a2, 4(s1)
    lw   a5, 0(s4)
    lw   t4, 0(s7)
    CHECK t4, 2, 47
    CHECK a5, 0xA5A5A5A5, 48
    lw   t4, 8(s7)
    la   t3, l6b
    CHECKR t4, t3, 49

# ---- 7. faulting load while a divide / multiply is behind it in EX (squashed)
    li   a6, 1000
    li   a7, 7
    RSTLOG
l7: lw   a2, 0(s1)
    div  t0, a6, a7
    rem  t1, a6, a7
    CHK_L 1, 5, l7, 0x20000100, 50
    CHECK t0, 142, 54
    CHECK t1, 6, 55
    li   a6, 12345
    li   a7, 321
    mul  t0, a6, a7
    mulh t1, a6, a7
    CHECK t0, 3962745, 56
    CHECK t1, 0, 57

# ---- 8. instruction access fault: jump to an error address
    la   t0, r8
    sw   t0, 20(s7)
    RSTLOG
    li   s6, 0x20000100
    jr   s6
r8: CHK_V 1, 1, 0x20000100, 0x20000100, 58

# ---- 9. ... at a halfword address (compressed alignment)
    la   t0, r9
    sw   t0, 20(s7)
    RSTLOG
    li   s6, 0x20000102
    jr   s6
r9: CHK_V 1, 1, 0x20000102, 0x20000102, 62

# ---- 10. 32-bit instruction whose upper half is in an error word: tval = address of the bad half
    la   t0, r10
    sw   t0, 20(s7)
    RSTLOG
    li   s6, 0x3BFFE
    jr   s6
r10: CHK_V 1, 1, 0x3BFFE, 0x3C000, 66

# ---- 11. a fetch error that is never executed (c.jr leaves before the error word) is ignored
    la   s5, r11
    RSTLOG

    li   s6, 0x3BFFC
    jr   s6
r11: lw  t4, 0(s7)
    CHECK t4, 0, 70

# ---- 12. same sequence with the load error right behind a taken branch (wrong-path loads are not issued)
    li   a2, 0x1234
    RSTLOG
    li   t0, 1
    bnez t0, over
    lw   a2, 0(s1)                   # not executed
over:
    lw   t4, 0(s7)
    CHECK t4, 0, 71
    CHECK a2, 0x1234, 72

# ---- 13. mstatus after an access fault: MIE cleared, MPIE old MIE
    csrsi mstatus, 8
    RSTLOG
l13: lw  a2, 0(s1)
    csrr t0, mstatus
    andi t0, t0, 0x88
    CHECK t0, 0x88, 73               # MIE restored by mret, MPIE = 1
    csrci mstatus, 8

# ---- 14. minstret does not count the faulting access
    RSTLOG
    csrr s3, minstret
    nop
    nop
    .option push
    .option norvc                    # force the 4-byte form: the handler count below assumes it
l14: lw  a2, 0(s1)
    .option pop
    nop
    nop
    csrr s4, minstret
    sub  s4, s4, s3
    # between the two reads: nop nop lw(fault, NOT counted) nop nop csrr(sample) -> 5 + handler
    # handler = fixed instruction count H (see below) ; require exactly 5 + H
    li   t0, 5+HANDLER_INSTRS
    CHECKR s4, t0, 74

pass:
    li   t4, 0x10000000
    li   t5, 1
    sw   t5, 0(t4)
1:  j    1b
fail:
    slli t5, t5, 1
    ori  t5, t5, 1
    li   t4, 0x10000000
    sw   t5, 0(t4)
1:  j    1b

    .balign 4
handler:
hstart:
    lw   s9, 0(s7)
    addi s9, s9, 1
    sw   s9, 0(s7)
    csrr s11, mcause
    sw   s11, 4(s7)
    csrr s9, mepc
    sw   s9, 8(s7)
    csrr s9, mtval
    sw   s9, 12(s7)
    lw   s9, 0(s2)
    sw   s9, 24(s7)
    li   s10, 1
    bne  s11, s10, 1f
    lw   s9, 20(s7)                       # instruction access fault: resume at the stored address
    csrw mepc, s9
    mret
1:  csrr s11, mepc                        # load/store: skip the faulting instruction (2 or 4 bytes)
    lhu  s10, 0(s11)
    andi s10, s10, 3
    addi s11, s11, 2
    addi s10, s10, -3
    bnez s10, 2f
    addi s11, s11, 2
2:  csrw mepc, s11
    mret
hend:

    .balign 4
good:
    .word 0xA5A5A5A5

# Instructions executed by the handler for a 4-byte load fault, up to and including mret:
# lw,addi,sw, csrr,sw, csrr,sw, csrr,sw, lw,sw, li, bne(not taken), csrr, lhu, andi, addi, addi, bnez(not taken), addi, csrw, mret

.section .hj, "ax"
    .option push
    .option rvc
    c.jr s5
    .option pop
.section .hs, "ax"
    .option push
    .option norvc
    addi a0, a0, 1
    .option pop
