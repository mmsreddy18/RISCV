# Directed self-checking test for rv_core (RV32IMC).
# CHECK reg, expected, test#   -> on mismatch jumps to `fail` with test# in t5.
# Result is reported by storing to 0x1000_0000 (1 = PASS, (n<<1)|1 = FAIL n).

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

.section .text.init
.globl _start
_start:
    li   sp, 0x5000

# ------------------------------------------------------------ 1. ALU
    li   a0, 100
    li   a1, 37
    add  a2, a0, a1
    CHECK a2, 137, 1
    sub  a2, a0, a1
    CHECK a2, 63, 2
    li   a0, 0xF0F0F0F0
    li   a1, 0x0FF00FF0
    and  a2, a0, a1
    CHECK a2, 0x00F000F0, 3
    or   a2, a0, a1
    CHECK a2, 0xFFF0FFF0, 4
    xor  a2, a0, a1
    CHECK a2, 0xFF00FF00, 5
    li   a0, 0x80000001
    li   a1, 4
    sll  a2, a0, a1
    CHECK a2, 0x10, 6
    srl  a2, a0, a1
    CHECK a2, 0x08000000, 7
    sra  a2, a0, a1
    CHECK a2, 0xF8000000, 8
    slli a2, a0, 1
    CHECK a2, 2, 9
    srai a2, a0, 31
    CHECK a2, 0xFFFFFFFF, 10
    srli a2, a0, 31
    CHECK a2, 1, 11
    li   a0, -1
    li   a1, 1
    slt  a2, a0, a1
    CHECK a2, 1, 12
    sltu a2, a0, a1
    CHECK a2, 0, 13
    slti a2, a0, 0
    CHECK a2, 1, 14
    sltiu a2, a0, -1
    CHECK a2, 0, 15
    sltiu a2, a1, -1
    CHECK a2, 1, 16
    lui  a2, 0x12345
    CHECK a2, 0x12345000, 17
    auipc a0, 0
    auipc a1, 0
    sub  a2, a1, a0
    CHECK a2, 4, 18

# ------------------------------------------------------------ 2. forwarding
    li   a0, 1
    add  a0, a0, a0
    add  a0, a0, a0
    add  a0, a0, a0          # 8
    add  a1, a0, a0          # 16
    add  a2, a1, a0          # 24  (dist 1 and dist 2)
    nop
    add  a3, a2, a0          # 32  (dist 2 and dist 4)
    CHECK a1, 16, 19
    CHECK a2, 24, 20
    CHECK a3, 32, 21

# ------------------------------------------------------------ 3. load/store
    la   s0, buf
    li   a0, 0x8899AABB
    sw   a0, 0(s0)
    lw   a1, 0(s0)
    add  a2, a1, zero        # load-use
    CHECK a2, 0x8899AABB, 22
    lb   a1, 0(s0)
    CHECK a1, 0xFFFFFFBB, 23
    lbu  a1, 1(s0)
    CHECK a1, 0xAA, 24
    lh   a1, 2(s0)
    CHECK a1, 0xFFFF8899, 25
    lhu  a1, 2(s0)
    CHECK a1, 0x8899, 26
    lb   a1, 3(s0)
    CHECK a1, 0xFFFFFF88, 27
    li   a0, 0x55
    sb   a0, 1(s0)
    lw   a1, 0(s0)
    CHECK a1, 0x889955BB, 28
    li   a0, 0x1234
    sh   a0, 2(s0)
    lw   a1, 0(s0)
    CHECK a1, 0x123455BB, 29
    lw   a1, 0(s0)
    sw   a1, 4(s0)           # store data comes from a load (stall)
    lw   a2, 4(s0)
    CHECK a2, 0x123455BB, 30
    sw   s0, 8(s0)
    lw   a1, 8(s0)
    lw   a2, 0(a1)           # load -> address dependency
    CHECK a2, 0x123455BB, 31
    # back-to-back stores/loads
    li   a0, 1
    li   a1, 2
    li   a2, 3
    sw   a0, 16(s0)
    sw   a1, 20(s0)
    sw   a2, 24(s0)
    lw   a3, 16(s0)
    lw   a4, 20(s0)
    lw   a5, 24(s0)
    add  a3, a3, a4
    add  a3, a3, a5
    CHECK a3, 6, 32

# ------------------------------------------------------------ 4. branches / jumps
    li   a0, 5
    li   a1, 5
    li   a2, 0
    beq  a0, a1, 1f
    li   a2, 1
1:  CHECK a2, 0, 33
    bne  a0, a1, 1f
    addi a2, a2, 2
1:  CHECK a2, 2, 34
    li   a0, -1
    li   a1, 1
    li   a2, 0
    blt  a0, a1, 1f
    addi a2, a2, 1
1:  bltu a0, a1, 2f
    addi a2, a2, 2
2:  bge  a0, a1, 3f
    addi a2, a2, 4
3:  bgeu a0, a1, 4f
    addi a2, a2, 8
4:  CHECK a2, 6, 35
    li   a0, 0
    li   a1, 10
1:  add  a0, a0, a1
    addi a1, a1, -1
    bnez a1, 1b
    CHECK a0, 55, 36
    # branch operand produced by the immediately preceding instruction
    li   a2, 0
    addi a0, zero, 9
    beq  a0, zero, 1f        # not taken, a0 forwarded from EX
    addi a2, a2, 1
1:  addi a0, zero, 0
    beqz a0, 2f              # taken, a0 forwarded from EX
    addi a2, a2, 2
2:  CHECK a2, 1, 37
    # branch operand from a load (load-use into branch)
    sw   zero, 28(s0)
    li   a2, 0
    lw   a0, 28(s0)
    bnez a0, 1f
    addi a2, a2, 1
1:  CHECK a2, 1, 38
    # jal / ret
    li   a2, 0
    jal  ra, func1
    addi a2, a2, 1
    CHECK a2, 11, 39
    j    after_func1
func1:
    addi a2, a2, 10
    ret
after_func1:
    # jalr with link register
    la   a0, jfunc
    jalr s1, 0(a0)
jret:
    la   a3, jret
    CHECKR s1, a3, 40
    j    jdone
jfunc:
    li   a2, 77
    jr   s1
jdone:
    CHECK a2, 77, 41
    # jalr clears target bit 0
    la   a0, jfunc2
    addi a0, a0, 1
    jalr zero, 0(a0)
    li   t5, 42
    j    fail
jfunc2:
    li   a2, 5
    CHECK a2, 5, 43
    # jalr through a loaded pointer
    la   a0, jfunc3
    sw   a0, 12(s0)
    lw   a1, 12(s0)
    jalr ra, 0(a1)
    j    jdone3
jfunc3:
    li   a2, 6
    ret
jdone3:
    CHECK a2, 6, 44

# ------------------------------------------------------------ 5. M extension
    li   a0, 7
    li   a1, 6
    mul  a2, a0, a1
    CHECK a2, 42, 50
    add  a3, a2, a2
    CHECK a3, 84, 51
    li   a0, -3
    li   a1, 5
    mul  a2, a0, a1
    CHECK a2, 0xFFFFFFF1, 52
    li   a0, 0x80000000
    li   a1, 2
    mulh a2, a0, a1
    CHECK a2, 0xFFFFFFFF, 53
    mulhu a2, a0, a1
    CHECK a2, 1, 54
    mulhsu a2, a0, a1
    CHECK a2, 0xFFFFFFFF, 55
    li   a0, 0xFFFFFFFF
    li   a1, 0xFFFFFFFF
    mulh a2, a0, a1
    CHECK a2, 0, 56
    mulhu a2, a0, a1
    CHECK a2, 0xFFFFFFFE, 57
    mulhsu a2, a0, a1
    CHECK a2, 0xFFFFFFFF, 58
    mul  a2, a0, a1
    CHECK a2, 1, 59
    li   a0, 100
    li   a1, 7
    div  a2, a0, a1
    CHECK a2, 14, 60
    rem  a2, a0, a1
    CHECK a2, 2, 61
    li   a0, -100
    div  a2, a0, a1
    CHECK a2, 0xFFFFFFF2, 62
    rem  a2, a0, a1
    CHECK a2, 0xFFFFFFFE, 63
    divu a2, a0, a1
    CHECK a2, 0x24924916, 64
    remu a2, a0, a1
    CHECK a2, 2, 65
    li   a1, 0
    div  a2, a0, a1
    CHECK a2, 0xFFFFFFFF, 66
    divu a2, a0, a1
    CHECK a2, 0xFFFFFFFF, 67
    rem  a2, a0, a1
    CHECK a2, 0xFFFFFF9C, 68
    remu a2, a0, a1
    CHECK a2, 0xFFFFFF9C, 69
    li   a0, 0x80000000
    li   a1, -1
    div  a2, a0, a1
    CHECK a2, 0x80000000, 70
    rem  a2, a0, a1
    CHECK a2, 0, 71
    li   a0, 100
    li   a1, 10
    div  a2, a0, a1
    li   a3, 0
    bne  a2, a1, 1f          # branch depends on a div result
    li   a3, 1
1:  CHECK a3, 1, 72
    # M op feeding a store and a load-dependent chain
    mul  a2, a0, a1
    sw   a2, 32(s0)
    lw   a4, 32(s0)
    CHECK a4, 1000, 73

# ------------------------------------------------------------ 6. compressed
    c.li   a0, 5
    c.addi a0, 3
    c.mv   a1, a0
    c.add  a1, a0
    CHECK  a1, 16, 80
    c.slli a0, 2
    CHECK  a0, 32, 81
    c.li   a2, -1
    c.srli a2, 28
    CHECK  a2, 15, 82
    c.li   a2, -16
    c.srai a2, 2
    CHECK  a2, 0xFFFFFFFC, 83
    c.andi a2, 7
    CHECK  a2, 4, 84
    c.li   a0, 12
    c.li   a1, 10
    c.sub  a0, a1
    CHECK  a0, 2, 85
    c.xor  a0, a1
    CHECK  a0, 8, 86
    c.or   a0, a1
    CHECK  a0, 10, 87
    c.li   a1, 6
    c.and  a0, a1
    CHECK  a0, 2, 88
    c.lui  a3, 3
    CHECK  a3, 0x3000, 89
    c.lui  a3, 0xfffff
    CHECK  a3, 0xFFFFF000, 90
    c.addi16sp sp, 32
    CHECK  sp, 0x5020, 91
    c.addi16sp sp, -64
    CHECK  sp, 0x4FE0, 92
    c.addi4spn a0, sp, 16
    li     a1, 0x4FF0
    CHECKR a0, a1, 93
    c.li   a1, 21
    c.sw   a1, 4(a0)
    c.lw   a2, 4(a0)
    CHECK  a2, 21, 94
    c.swsp a1, 8(sp)
    c.lwsp a3, 8(sp)
    CHECK  a3, 21, 95
    c.li   a0, 0
    c.beqz a0, 1f
    c.li   a0, 1
1:  CHECK  a0, 0, 96
    c.li   a0, 3
    c.bnez a0, 2f
    c.li   a0, 1
2:  CHECK  a0, 3, 97
    c.j    3f
    c.li   a0, 7
3:  CHECK  a0, 3, 98
    c.jal  cfunc
    CHECK  a0, 4, 99
    c.j    after_cfunc
cfunc:
    c.addi a0, 1
    c.jr   ra
after_cfunc:
    la     a1, cfunc2
    c.jalr a1
    CHECK  a0, 14, 100
    c.j    after_cfunc2
cfunc2:
    c.addi a0, 10
    c.jr   ra
after_cfunc2:
    # 32-bit instructions at halfword offsets (straddling word boundaries)
    c.li   a0, 0
    c.j    tgt1
    c.li   a0, 25
    .balign 4
    c.nop
tgt1:
    .option push
    .option norvc
    addi   a0, a0, 1
    addi   a0, a0, 2
    addi   a0, a0, 4
    .option pop
    CHECK  a0, 7, 101
    # taken branch to a halfword-aligned 32-bit instruction, then more mixed code
    c.li   a1, 0
    c.beqz a1, tgt2
    c.li   a0, 29
    .balign 4
    c.nop
tgt2:
    .option push
    .option norvc
    addi   a0, a0, 8
    .option pop
    c.addi a0, 1
    .option push
    .option norvc
    addi   a0, a0, 16
    .option pop
    CHECK  a0, 32, 102

# ------------------------------------------------------------ pass
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

.section .data
.balign 4
buf: .space 64
