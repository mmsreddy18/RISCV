# Directed self-checking test: Zicsr + machine-mode traps/interrupts for rv_core.
# Result: store to 0x1000_0000 (1 = PASS, (n<<1)|1 = FAIL test n).
# Register use: s7 = log base, s8..s11 = trap-handler temporaries (tests must not use them).
# TB MMIO:  0x10000010 sw-irq level, 0x10000014 ext-irq level, 0x10000018 timer (N cycles / 0 clear)
#
# Trap log (LOG = 0x4800, in s7):
#   +0 count   +4 last cause   +8 last mepc   +12 last mtval   +16 vector marker
#   +32+4*i  ack MMIO address for event i (store zero there from the handler, interrupts only)
#   +64+4*i  cause[i]   +128+4*i mepc[i]   +192+4*i mstatus seen in handler [i]   +256+4*i mtval[i]

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

.macro SETACK idx, addr
    li   t4, \addr
    sw   t4, 32+4*\idx(s7)
.endm

# after an exception: count, cause, mepc == label, mtval
.macro CHK_EXC cnt, cause, lbl, tval, num
    lw   t4, 0(s7)
    CHECK t4, \cnt, \num
    lw   t4, 4(s7)
    CHECK t4, \cause, \num+1
    lw   t4, 8(s7)
    la   t3, \lbl
    CHECKR t4, t3, \num+2
    .if \tval+1
    lw   t4, 12(s7)
    CHECK t4, \tval, \num+3
    .endif
.endm

.section .text.init
.globl _start
_start:
    li   sp, 0x5000
    li   s7, 0x4800
    la   t0, handler
    csrw mtvec, t0
    sw   zero, 0(s7)
    la   s1, buf

# =========================================================== 1. CSR instructions
    li   a0, 0xF0F0
    csrw mscratch, a0
    csrr a1, mscratch
    CHECKR a1, a0, 1
    li   a1, 0x0FF0
    csrrs a2, mscratch, a1          # returns old, sets bits
    CHECK a2, 0xF0F0, 2
    csrr a3, mscratch
    CHECK a3, 0xFFF0, 3
    csrrc a2, mscratch, a1          # returns old, clears bits
    CHECK a2, 0xFFF0, 4
    csrr a3, mscratch
    CHECK a3, 0xF000, 5
    csrrwi a2, mscratch, 21
    CHECK a2, 0xF000, 6
    csrrsi a2, mscratch, 10
    CHECK a2, 21, 7
    csrrci a2, mscratch, 5
    CHECK a2, 31, 8
    csrr a3, mscratch
    CHECK a3, 26, 9
    csrrw a2, mscratch, a1          # swap
    CHECK a2, 26, 10
    csrrs a2, mscratch, zero        # no write
    CHECK a2, 0x0FF0, 11
    csrrs a2, mscratch, zero
    CHECK a2, 0x0FF0, 12
    csrrw zero, mscratch, zero      # rd = x0 write
    csrr a2, mscratch
    CHECK a2, 0, 13
    # read-only CSRs readable with rs1 = x0, no trap
    csrr a2, mhartid
    CHECK a2, 0, 14
    csrr a2, misa
    CHECK a2, 0x40001104, 15
    csrr a2, mvendorid
    csrrs a2, marchid, zero
    csrrsi a2, mimpid, 0
    lw   t4, 0(s7)
    CHECK t4, 0, 16
    # WARL behaviour
    csrw misa, zero
    csrr a2, misa
    CHECK a2, 0x40001104, 17
    li   a0, 0x1235
    csrw mepc, a0
    csrr a2, mepc
    CHECK a2, 0x1234, 18                   # bit 0 reads zero
    li   a0, -1
    csrw mie, a0
    csrr a2, mie
    CHECK a2, 0x888, 19
    csrw mie, zero
    csrw mip, a0
    csrr a2, mip
    CHECK a2, 0, 20                        # mip bits are read-only
    li   a0, 0x103
    csrw mtvec, a0
    csrr a2, mtvec
    CHECK a2, 0x101, 21                    # bit 1 hard-wired 0
    la   t0, handler
    csrw mtvec, t0
    li   a0, 0x80000005
    csrw mcause, a0
    csrr a2, mcause
    CHECK a2, 0x80000005, 22
    li   a0, 0xDEADBEEF
    csrw mtval, a0
    csrr a2, mtval
    CHECK a2, 0xDEADBEEF, 23
    csrw mstatus, 8
    csrr a2, mstatus
    CHECK a2, 0x1808, 24                   # MPP = 11 reads back
    li   a0, 0x88
    csrw mstatus, a0
    csrr a2, mstatus
    CHECK a2, 0x1888, 25
    csrw mstatus, zero
    csrr a2, mstatus
    CHECK a2, 0x1800, 26
    csrsi mstatus, 8
    csrr a2, mstatus
    CHECK a2, 0x1808, 27
    csrci mstatus, 8
    csrr a2, mstatus
    CHECK a2, 0x1800, 28
    wfi                                    # NOP
    nop

# ---- counters
    csrr a0, minstret
    nop
    nop
    nop
    csrr a1, minstret
    sub  a2, a1, a0
    CHECK a2, 4, 30                        # csrr + 3 nops retired in between
    csrr a0, cycle
    csrr a1, cycle
    bltu a0, a1, 1f
    li   t5, 31
    j    fail
1:  li   a0, 100
    csrw minstret, a0
    csrr a0, minstret
    nop
    csrr a1, minstret
    CHECK a0, 100, 32                      # csrw takes effect, csrw itself not added
    sub  a2, a1, a0
    CHECK a2, 2, 33
    csrr a0, instret                       # shadow, read-only
    csrr a1, minstret
    sub  a2, a1, a0
    CHECK a2, 1, 34
    csrr a0, mcycleh
    CHECK a0, 0, 35
    csrr a0, minstreth
    CHECK a0, 0, 36
    li   a0, -1
    csrw mcycle, a0
    nop
    nop
    nop
    csrr a2, mcycleh                       # low word wrapped: carry into the high word
    CHECK a2, 1, 37
    csrw mcycle, zero
    csrw mcycleh, zero
    li   a0, 5
    csrw mcountinhibit, a0                 # stop cycle and instret
    csrr a1, minstret
    nop
    csrr a2, minstret
    CHECKR a1, a2, 38
    csrr a1, mcycle
    nop
    csrr a2, mcycle
    CHECKR a1, a2, 39
    csrw mcountinhibit, zero
    csrr a1, mcycle
    nop
    csrr a2, mcycle
    bne  a1, a2, 1f
    li   t5, 40
    j    fail
1:

# ---- illegal CSR accesses trap (cause 2), rd and CSR unchanged, handler skips them
    RSTLOG
    li   a0, 0x55
ev_c1: csrw mhartid, a0                    # write to read-only
    CHK_EXC 1, 2, ev_c1, 0, 41
    li   a0, 0x55
ev_c2: csrr a0, 0x7C0                      # non-existent CSR
    CHK_EXC 2, 2, ev_c2, 0, 45
    CHECK a0, 0x55, 49                     # rd not written
ev_c3: csrrsi a2, mvendorid, 1             # set bit in read-only CSR
    CHK_EXC 3, 2, ev_c3, 0, 50
    li   a1, 1
ev_c4: csrrs a2, mhartid, a1
    CHK_EXC 4, 2, ev_c4, 0, 54
    li   a1, 0
    csrrs a2, mhartid, a1                  # rs1 = x0 value 0 but register form: rs1 field != 0 -> write attempt
    lw   t4, 0(s7)
    CHECK t4, 5, 58                        # (a1 is x11, so this IS a write attempt) -> trapped
ev_c5: csrrw a2, 0x340, a1                 # mscratch OK, must not trap
    lw   t4, 0(s7)
    CHECK t4, 5, 59

# =========================================================== 2. exceptions
    RSTLOG
    li   a0, 1
ev_e1: ecall
    addi a0, a0, 1
    CHECK a0, 2, 60
    CHK_EXC 1, 11, ev_e1, 0, 61
ev_e2: ebreak
    addi a0, a0, 1
    CHECK a0, 3, 65
    CHK_EXC 2, 3, ev_e2, 0, 66
    li   a5, 7
ev_e3: .word 0x000007FF                    # illegal, rd = a5 must stay untouched
    CHECK a5, 7, 70
    CHK_EXC 3, 2, ev_e3, 0, 71
ev_e4: .2byte 0x0000                       # illegal compressed instruction
    CHK_EXC 4, 2, ev_e4, 0, 75
ev_e5: .word 0x0000000B                    # custom-0 opcode: illegal
    CHK_EXC 5, 2, ev_e5, 0, 79
ev_e6: .word 0x40001033                    # sll with funct7 = 0100000: illegal
    CHK_EXC 6, 2, ev_e6, 0, 83
ev_e7: .word 0x0000100F                    # fence.i: illegal (Zifencei not implemented)
    CHK_EXC 7, 2, ev_e7, 0, 87
    # an instruction in the shadow of a taken branch must not trap
    li   t0, 1
    bnez t0, 1f
    ecall
    ebreak
1:  lw   t4, 0(s7)
    CHECK t4, 7, 91
    # trap after a multi-cycle divide: result of the divide must be intact
    li   a1, 100000
    li   a2, 7
    div  a3, a1, a2
ev_e8: ecall
    CHECK a3, 14285, 92
    CHK_EXC 8, 11, ev_e8, 0, 93
    # trap right behind a load (load-use not involved) and behind a mul
    lw   a4, 0(s1)
ev_e9: ebreak
    mul  a5, a2, a2
ev_e10: ebreak
    CHECK a5, 49, 97
    lw   t4, 0(s7)
    CHECK t4, 10, 98
    # many traps in a loop (predictor + flush stress)
    RSTLOG
    li   a0, 0
    li   a1, 20
lp_e: addi a0, a0, 1
    ecall
    bne  a0, a1, lp_e
    lw   t4, 0(s7)
    CHECK t4, 20, 99
    CHECK a0, 20, 100

# =========================================================== 3. misaligned load / store
    li   t0, 0x11223344
    sw   t0, 0(s1)
    li   t0, 0x55667788
    sw   t0, 4(s1)
    RSTLOG
    li   a0, 0x77
m_lw1: lw a0, 1(s1)
    CHECK a0, 0x77, 101                    # rd not written
    CHK_EXC 1, 4, m_lw1, -1, 102           # mtval checked below
    lw   t4, 12(s7)
    addi t3, s1, 1
    CHECKR t4, t3, 106
m_lw2: lw a0, 2(s1)
    lw   t4, 12(s7)
    addi t3, s1, 2
    CHECKR t4, t3, 107
m_lw3: lw a0, 3(s1)
    lw   t4, 12(s7)
    addi t3, s1, 3
    CHECKR t4, t3, 108
m_lh1: lh a0, 1(s1)
    lw   t4, 4(s7)
    CHECK t4, 4, 109
    lw   t4, 12(s7)
    addi t3, s1, 1
    CHECKR t4, t3, 110
m_lhu: lhu a0, 3(s1)
    lw   t4, 0(s7)
    CHECK t4, 5, 111
    CHECK a0, 0x77, 112
    # stores: cause 6, memory unchanged
    li   a1, 0xAABBCCDD
m_sw1: sw a1, 1(s1)
    lw   t4, 4(s7)
    CHECK t4, 6, 113
    lw   t4, 8(s7)
    la   t3, m_sw1
    CHECKR t4, t3, 114
    lw   t4, 12(s7)
    addi t3, s1, 1
    CHECKR t4, t3, 115
m_sw2: sw a1, 2(s1)
m_sh1: sh a1, 1(s1)
m_sh3: sh a1, 3(s1)
    lw   t4, 0(s7)
    CHECK t4, 9, 116
    lw   t4, 0(s1)
    li   t3, 0x11223344
    CHECKR t4, t3, 117
    lw   t4, 4(s1)
    li   t3, 0x55667788
    CHECKR t4, t3, 118
    # aligned and byte accesses never trap
    sb   a1, 1(s1)
    sb   a1, 3(s1)
    sh   a1, 2(s1)
    lb   a2, 1(s1)
    lbu  a2, 3(s1)
    lh   a2, 2(s1)
    lhu  a2, 6(s1)
    lw   a2, 4(s1)
    lw   t4, 0(s7)
    CHECK t4, 9, 119
    # instruction after a faulting store runs exactly once and the faulting one has no effect
    li   a3, 10
    sw   a1, 1(s1)
    addi a3, a3, 1
    CHECK a3, 11, 120
    li   a3, 10
    lw   a4, 3(s1)
    add  a3, a3, a3                        # consumer of the faulting load: sees old a4, runs once
    CHECK a3, 20, 121
    # branch right after a faulting access (must be squashed until the handler returns)
    li   a3, 0
    sh   a1, 1(s1)
    beqz a3, 1f
    li   a3, 99
1:  addi a3, a3, 1
    CHECK a3, 1, 122

# =========================================================== 4. mstatus on trap / mret
    RSTLOG
    csrsi mstatus, 8                       # MIE = 1
ev_s1: ecall
    lw   t4, 192(s7)                       # mstatus seen in the handler (index 0 at +192? count=1 -> +192)
    li   t6, 0x88
    and  t4, t4, t6
    CHECK t4, 0x80, 130                    # MPIE=1, MIE=0 inside the handler
    csrr a2, mstatus
    li   t6, 0x88
    and  a2, a2, t6
    CHECK a2, 0x88, 131                    # after mret: MIE=1, MPIE=1
    csrci mstatus, 8
ev_s2: ecall
    lw   t4, 196(s7)
    li   t6, 0x88
    and  t4, t4, t6
    CHECK t4, 0x00, 132                    # MPIE=0, MIE=0
    csrr a2, mstatus
    li   t6, 0x88
    and  a2, a2, t6
    CHECK a2, 0x80, 133                    # after mret: MIE=0, MPIE=1

# =========================================================== 5. CSR-trap hazards
    la   t0, handler2
    csrw mtvec, t0                         # immediately followed by a trap: must use the new mtvec
    ecall
    la   t0, handler
    csrw mtvec, t0
    lw   t4, 16(s7)
    CHECK t4, 0x2222, 134                  # handler2 ran
    la   t0, resume1
    li   a0, 0
    csrw mepc, t0                          # mepc written, mret right behind
    mret
    li   a0, 99                            # must be skipped
resume1:
    CHECK a0, 0, 135

# =========================================================== 6. interrupts
    RSTLOG
    li   t4, 0
    sw   t4, 32(s7)
    sw   t4, 36(s7)
    sw   t4, 40(s7)
    sw   t4, 44(s7)
# ---- 6a software interrupt
    SETACK 0, 0x10000010
    li   t0, 8
    csrw mie, t0
    csrsi mstatus, 8
    li   t0, 0x10000010
    li   t1, 1
    sw   t1, 0(t0)
s6a: li   a0, 0
    li   a1, 200
w6a: addi a0, a0, 1
    lw   t4, 0(s7)
    bnez t4, d6a
    blt  a0, a1, w6a
d6a:
    lw   t4, 0(s7)
    CHECK t4, 1, 140
    lw   t4, 4(s7)
    CHECK t4, 0x80000003, 141
    lw   t4, 8(s7)
    la   t3, s6a
    bltu t4, t3, bad6a
    la   t3, d6a
    bgtu t4, t3, bad6a
    j    ok6a
bad6a: li t5, 142
    j    fail
ok6a:
    csrci mstatus, 8
    csrw mie, zero
# ---- 6b timer interrupt
    RSTLOG
    SETACK 0, 0x10000018
    li   t0, 0x80
    csrw mie, t0
    csrsi mstatus, 8
    li   t0, 0x10000018
    li   t1, 60
    sw   t1, 0(t0)
    li   a0, 0
    li   a1, 400
w6b: addi a0, a0, 1
    lw   t4, 0(s7)
    bnez t4, d6b
    blt  a0, a1, w6b
d6b:
    lw   t4, 0(s7)
    CHECK t4, 1, 143
    lw   t4, 4(s7)
    CHECK t4, 0x80000007, 144
    csrci mstatus, 8
    csrw mie, zero
# ---- 6c external interrupt
    RSTLOG
    SETACK 0, 0x10000014
    li   t0, 0x800
    csrw mie, t0
    csrsi mstatus, 8
    li   t0, 0x10000014
    li   t1, 1
    sw   t1, 0(t0)
    li   a0, 0
    li   a1, 200
w6c: addi a0, a0, 1
    lw   t4, 0(s7)
    bnez t4, d6c
    blt  a0, a1, w6c
d6c:
    lw   t4, 0(s7)
    CHECK t4, 1, 145
    lw   t4, 4(s7)
    CHECK t4, 0x8000000B, 146
    csrci mstatus, 8
    csrw mie, zero
# ---- 6d priority: external > software > timer, all pending together
    RSTLOG
    SETACK 0, 0x10000014
    SETACK 1, 0x10000010
    SETACK 2, 0x10000018
    li   t0, 0x888
    csrw mie, t0
    li   t0, 0x10000014
    li   t1, 1
    sw   t1, 0(t0)
    li   t0, 0x10000010
    sw   t1, 0(t0)
    li   t0, 0x10000018
    sw   t1, 0(t0)                         # timer after 1 cycle
    li   a0, 0
w6d0: addi a0, a0, 1
    li   t4, 40
    blt  a0, t4, w6d0                      # let all three become pending (MIE still 0)
    lw   t4, 0(s7)
    CHECK t4, 0, 147                       # nothing taken while MIE = 0
    csrsi mstatus, 8
    li   a0, 0
    li   a1, 300
w6d: addi a0, a0, 1
    lw   t4, 0(s7)
    li   t3, 3
    beq  t4, t3, d6d
    blt  a0, a1, w6d
d6d:
    lw   t4, 0(s7)
    CHECK t4, 3, 148
    lw   t4, 64(s7)
    CHECK t4, 0x8000000B, 149
    lw   t4, 68(s7)
    CHECK t4, 0x80000003, 150
    lw   t4, 72(s7)
    CHECK t4, 0x80000007, 151
    csrci mstatus, 8
    csrw mie, zero
# ---- 6e masking: mie bit clear / MIE clear => no interrupt
    RSTLOG
    SETACK 0, 0x10000010
    li   t0, 0x80
    csrw mie, t0                           # only timer enabled
    csrsi mstatus, 8
    li   t0, 0x10000010
    li   t1, 1
    sw   t1, 0(t0)                         # software line asserted but masked
    li   a0, 0
w6e: addi a0, a0, 1
    li   t4, 60
    blt  a0, t4, w6e
    lw   t4, 0(s7)
    CHECK t4, 0, 152
    csrci mstatus, 8
    li   t0, 8
    csrw mie, t0                           # enabled in mie, but MIE = 0
    li   a0, 0
w6e2: addi a0, a0, 1
    li   t4, 60
    blt  a0, t4, w6e2
    lw   t4, 0(s7)
    CHECK t4, 0, 153
    csrsi mstatus, 8                       # now it must fire
    li   a0, 0
w6e3: addi a0, a0, 1
    lw   t4, 0(s7)
    bnez t4, d6e
    li   t4, 100
    blt  a0, t4, w6e3
d6e:
    lw   t4, 0(s7)
    CHECK t4, 1, 154
    csrci mstatus, 8
    csrw mie, zero
# ---- 6f interrupt in the middle of a busy loop (loads, stores, divides, branches)
    RSTLOG
    SETACK 0, 0x10000018
    sw   zero, 0(s1)
    li   t0, 0x80
    csrw mie, t0
    csrsi mstatus, 8
    li   t0, 0x10000018
    li   t1, 120
    sw   t1, 0(t0)
    li   a0, 0
    li   a1, 0
    li   a2, 300
    li   s2, 12345
    li   s3, 7
    li   s4, 0
    li   s5, 0
lp6f: addi a0, a0, 1
    addi a1, a1, 3
    lw   t0, 0(s1)
    addi t0, t0, 1
    sw   t0, 0(s1)
    divu t1, s2, s3
    add  s4, s4, t1
    mul  t2, a0, a0
    add  s5, s5, t2
    bne  a0, a2, lp6f
    csrci mstatus, 8
    csrw mie, zero
    CHECK a0, 300, 155                     # every instruction executed exactly once
    CHECK a1, 900, 156
    lw   t0, 0(s1)
    CHECK t0, 300, 157
    CHECK s4, 528900, 158                  # 300 * (12345 / 7)
    lw   t4, 0(s7)
    CHECK t4, 1, 159
    lw   t4, 8(s7)
    la   t3, lp6f
    bltu t4, t3, bad6f
    la   t3, lp6f+44
    bgtu t4, t3, bad6f
    j    ok6f
bad6f: li t5, 160
    j    fail
ok6f:
    # sum of squares 1..300 = 300*301*601/6 = 9045050
    CHECK s5, 9045050, 161
# ---- 6g interrupts see the final mstatus after a CSR write (MPIE must always be 1)
    RSTLOG
    SETACK 0, 0x10000010
    li   t0, 8
    csrw mie, t0
    li   t0, 0x10000010
    li   t1, 1
    sw   t1, 0(t0)                         # pending while MIE = 0
    li   a0, 0
    li   a1, 60
lp6g: csrsi mstatus, 8
    nop
    nop
    csrci mstatus, 8
    addi a0, a0, 1
    bne  a0, a1, lp6g
    lw   t4, 0(s7)
    CHECK t4, 1, 162                       # exactly one interrupt
    lw   t4, 192(s7)
    li   t6, 0x80
    and  t4, t4, t6
    CHECK t4, 0x80, 163                    # taken with MIE = 1 (MPIE = 1)
    csrw mie, zero
    csrr a2, mstatus
    CHECK a2, 0x1880, 164                  # MIE = 0 (csrci ran), MPIE = 1 (from mret)
# ---- 6h vectored mode: interrupts to base+4*cause, exceptions to base
    RSTLOG
    SETACK 0, 0x10000010
    SETACK 1, 0x10000018
    SETACK 2, 0x10000014
    la   t0, vtable
    ori  t0, t0, 1
    csrw mtvec, t0
    li   t0, 8
    csrw mie, t0
    csrsi mstatus, 8
    li   t0, 0x10000010
    li   t1, 1
    sw   t1, 0(t0)
    li   a0, 0
w6h: addi a0, a0, 1
    lw   t4, 0(s7)
    bnez t4, d6h
    li   t4, 200
    blt  a0, t4, w6h
d6h:
    lw   t4, 16(s7)
    CHECK t4, 3, 165                       # vector 3
    li   t0, 0x80
    csrw mie, t0
    li   t0, 0x10000018
    li   t1, 40
    sw   t1, 0(t0)
    li   a0, 0
w6h2: addi a0, a0, 1
    lw   t4, 0(s7)
    li   t3, 2
    beq  t4, t3, d6h2
    li   t4, 300
    blt  a0, t4, w6h2
d6h2:
    lw   t4, 16(s7)
    CHECK t4, 7, 166                       # vector 7
    li   t0, 0x800
    csrw mie, t0
    li   t0, 0x10000014
    li   t1, 1
    sw   t1, 0(t0)
    li   a0, 0
w6h3: addi a0, a0, 1
    lw   t4, 0(s7)
    li   t3, 3
    beq  t4, t3, d6h3
    li   t4, 300
    blt  a0, t4, w6h3
d6h3:
    lw   t4, 16(s7)
    CHECK t4, 11, 167                      # vector 11
    csrci mstatus, 8
    csrw mie, zero
ev_v0: ecall                               # exception in vectored mode -> base (entry 0)
    lw   t4, 16(s7)
    CHECK t4, 0, 168
    la   t0, handler
    csrw mtvec, t0

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

# ------------------------------------------------------------ trap handlers
    .balign 4
handler:
    lw   s9, 0(s7)
    addi s9, s9, 1
    sw   s9, 0(s7)                         # count
    slli s10, s9, 2
    add  s10, s10, s7                      # s10 = LOG + 4*count
    csrr s11, mcause
    sw   s11, 4(s7)
    sw   s11, 60(s10)                      # cause[count-1]
    csrr s9, mepc
    sw   s9, 8(s7)
    sw   s9, 124(s10)                      # mepc[count-1]
    csrr s9, mstatus
    sw   s9, 188(s10)                      # mstatus[count-1]
    csrr s9, mtval
    sw   s9, 12(s7)
    sw   s9, 252(s10)
    bltz s11, hirq
    csrr s11, mepc                         # exception: skip the faulting instruction
    lhu  s10, 0(s11)
    andi s10, s10, 3
    addi s11, s11, 2
    addi s10, s10, -3
    bnez s10, 1f
    addi s11, s11, 2
1:  csrw mepc, s11
    mret
hirq:
    lw   s9, 28(s10)                       # ack address for this event
    beqz s9, 1f
    sw   zero, 0(s9)
1:  nop                                    # let the cleared line propagate before MIE comes back
    nop
    nop
    nop
    nop
    mret

    .balign 4
handler2:                                  # marker handler (checks mtvec update ordering)
    li   s9, 0x2222
    sw   s9, 16(s7)
    csrr s11, mepc
    addi s11, s11, 4
    csrw mepc, s11
    mret

hvc:                                       # common vectored tail: s9 = vector number
    sw   s9, 16(s7)
    j    handler_v
handler_v:
    lw   s10, 0(s7)
    addi s10, s10, 1
    sw   s10, 0(s7)
    csrr s11, mcause
    bltz s11, hvirq
    csrr s11, mepc                         # exception: skip 4 (ecall is always 4 bytes here)
    addi s11, s11, 4
    csrw mepc, s11
    mret
hvirq:
    slli s10, s10, 2
    add  s10, s10, s7
    lw   s9, 28(s10)
    beqz s9, 1f
    sw   zero, 0(s9)
1:  nop
    nop
    nop
    nop
    nop
    mret

    .balign 64
vtable:
    .option push
    .option norvc
    j    hv0
    j    hv_bad
    j    hv_bad
    j    hv3
    j    hv_bad
    j    hv_bad
    j    hv_bad
    j    hv7
    j    hv_bad
    j    hv_bad
    j    hv_bad
    j    hv11
    .option pop
hv0:  li s9, 0
    j hvc
hv3:  li s9, 3
    j hvc
hv7:  li s9, 7
    j hvc
hv11: li s9, 11
    j hvc
hv_bad:
    li   t5, 169
    j    fail

.section .data
.balign 4
buf: .space 64
