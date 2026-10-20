// -----------------------------------------------------------------------------
// rv_csr.sv : machine-mode CSR file (Zicsr) + trap / interrupt state
//
//   Implemented CSRs (M-mode only):
//     0x300 mstatus   MIE[3] MPIE[7], MPP[12:11] reads 2'b11 (hard-wired)
//     0x301 misa      RV32 I M C  (read-only; writes ignored = WARL)
//     0x304 mie       MSIE[3] MTIE[7] MEIE[11]
//     0x305 mtvec     BASE[31:2], MODE[0] (0 = direct, 1 = vectored interrupts)
//     0x320 mcountinhibit  CY[0] IR[2]
//     0x340 mscratch  0x341 mepc  0x342 mcause  0x343 mtval
//     0x344 mip       MSIP[3] MTIP[7] MEIP[11], read-only (driven by the irq pins)
//     0xB00/0xB80 mcycle/mcycleh   0xB02/0xB82 minstret/minstreth
//     0xC00/0xC80 cycle/cycleh     0xC02/0xC82 instret/instreth (read-only shadows)
//     0xF11 mvendorid 0xF12 marchid 0xF13 mimpid 0xF14 mhartid (read-only)
//   Any other address, or a write to a read-only (addr[11:10]==2'b11) CSR, is an
//   illegal-instruction exception (chk_illegal_o, evaluated by the core in ID).
//
//   Access protocol (core side)
//     * read  : combinational csr_rdata_o for addr_i (used by the instruction in EX)
//     * write : wr_i pulse in the cycle the CSR instruction leaves EX
//     * trap  : trap_i pulse (one cycle) with pc / cause / tval; updates mepc, mcause,
//               mtval, mstatus.{MPIE<=MIE, MIE<=0}
//     * mret  : mret_i pulse; mstatus.{MIE<=MPIE, MPIE<=1}
//     * The core guarantees a CSR write and a trap/mret never occur in the same cycle.
// -----------------------------------------------------------------------------
module rv_csr #(
  parameter logic [31:0] MTVEC_RESET = 32'h0000_0000
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [31:0] hart_id_i,

  // interrupt request lines (levels, sampled by one flop)
  input  logic        irq_software_i,
  input  logic        irq_timer_i,
  input  logic        irq_external_i,

  // ID-side legality check of a CSR instruction
  input  logic [11:0] chk_addr_i,
  input  logic        chk_write_i,
  output logic        chk_illegal_o,

  // EX-side access
  input  logic [11:0] addr_i,
  input  logic [1:0]  op_i,          // 01 = RW, 10 = RS, 11 = RC
  input  logic [31:0] wdata_i,       // rs1 value or zero-extended uimm
  input  logic        wr_i,          // commit the write now
  output logic [31:0] rdata_o,

  // retired instructions this cycle (0..2)
  input  logic [1:0]  instret_inc_i,
  input  logic        instret_dec_i,   // an instruction counted at EX exit faulted in WB: it does not retire

  // trap / return
  input  logic        trap_i,
  input  logic        trap_irq_i,
  input  logic [4:0]  trap_cause_i,
  input  logic [31:0] trap_pc_i,
  input  logic [31:0] trap_tval_i,
  input  logic        mret_i,

  output logic [31:0] mepc_o,
  output logic [31:0] trap_vec_o,    // target for the trap described by trap_irq_i/trap_cause_i
  output logic        irq_pending_o, // an enabled interrupt is pending and mstatus.MIE = 1
  output logic [4:0]  irq_cause_o    // cause of the highest-priority pending interrupt
);

  localparam logic [31:0] MISA = 32'h4000_1104;   // MXL=1, I(8) M(12) C(2)

  // ---------------------------------------------------------------- state
  logic        mie_q, mpie_q;                // mstatus
  logic [11:0] mie_r_q;                      // only bits 3/7/11 used
  logic [31:2] mtvec_base_q;
  logic        mtvec_mode_q;
  logic [31:0] mscratch_q, mepc_q, mtval_q;
  logic        mcause_irq_q;
  logic [4:0]  mcause_code_q;
  logic        inh_cy_q, inh_ir_q;
  logic [63:0] mcycle_q, minstret_q;
  logic [11:0] mip_q;                        // sampled irq lines (bits 3/7/11)

  // ---------------------------------------------------------------- interrupt lines
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) mip_q <= 12'h0;
    else         mip_q <= {irq_external_i, 3'b000, irq_timer_i, 3'b000, irq_software_i, 3'b000};
  end

  logic [11:0] irq_active;
  assign irq_active    = mip_q & mie_r_q;
  assign irq_pending_o = mie_q & (|irq_active);
  // priority: external (11) > software (3) > timer (7)
  assign irq_cause_o   = irq_active[11] ? 5'd11 : irq_active[3] ? 5'd3 : 5'd7;

  // ---------------------------------------------------------------- legality
  logic csr_exists;
  always_comb begin
    unique case (chk_addr_i)
      12'h300, 12'h301, 12'h304, 12'h305, 12'h320,
      12'h340, 12'h341, 12'h342, 12'h343, 12'h344,
      12'hB00, 12'hB02, 12'hB80, 12'hB82,
      12'hC00, 12'hC02, 12'hC80, 12'hC82,
      12'hF11, 12'hF12, 12'hF13, 12'hF14: csr_exists = 1'b1;
      default:                            csr_exists = 1'b0;
    endcase
  end
  assign chk_illegal_o = ~csr_exists | (chk_write_i & (chk_addr_i[11:10] == 2'b11));

  // ---------------------------------------------------------------- read
  always_comb begin
    unique case (addr_i)
      12'h300: rdata_o = {19'h0, 2'b11, 3'b000, mpie_q, 3'b000, mie_q, 3'b000};
      12'h301: rdata_o = MISA;
      12'h304: rdata_o = {20'h0, mie_r_q};
      12'h305: rdata_o = {mtvec_base_q, 1'b0, mtvec_mode_q};
      12'h320: rdata_o = {29'h0, inh_ir_q, 1'b0, inh_cy_q};
      12'h340: rdata_o = mscratch_q;
      12'h341: rdata_o = mepc_q;
      12'h342: rdata_o = {mcause_irq_q, 26'h0, mcause_code_q};
      12'h343: rdata_o = mtval_q;
      12'h344: rdata_o = {20'h0, mip_q};
      12'hB00, 12'hC00: rdata_o = mcycle_q[31:0];
      12'hB80, 12'hC80: rdata_o = mcycle_q[63:32];
      12'hB02, 12'hC02: rdata_o = minstret_q[31:0];
      12'hB82, 12'hC82: rdata_o = minstret_q[63:32];
      12'hF11, 12'hF12, 12'hF13: rdata_o = 32'h0;
      12'hF14: rdata_o = hart_id_i;
      default: rdata_o = 32'h0;
    endcase
  end

  // ---------------------------------------------------------------- write value
  logic [31:0] wval;
  always_comb begin
    unique case (op_i)
      2'b01:   wval = wdata_i;
      2'b10:   wval = rdata_o |  wdata_i;
      default: wval = rdata_o & ~wdata_i;
    endcase
  end

  assign mepc_o = mepc_q;

  logic [31:0] vec_base;
  assign vec_base   = {mtvec_base_q, 2'b00};
  assign trap_vec_o = (trap_irq_i && mtvec_mode_q) ? (vec_base + {25'h0, trap_cause_i, 2'b00})
                                                    : vec_base;

  // ---------------------------------------------------------------- update
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mie_q         <= 1'b0;
      mpie_q        <= 1'b0;
      mie_r_q       <= 12'h0;
      mtvec_base_q  <= MTVEC_RESET[31:2];
      mtvec_mode_q  <= MTVEC_RESET[0];
      mscratch_q    <= 32'h0;
      mepc_q        <= 32'h0;
      mtval_q       <= 32'h0;
      mcause_irq_q  <= 1'b0;
      mcause_code_q <= 5'h0;
      inh_cy_q      <= 1'b0;
      inh_ir_q      <= 1'b0;
      mcycle_q      <= 64'h0;
      minstret_q    <= 64'h0;
    end else begin
      // counters free-run / count retirements unless inhibited
      if (!inh_cy_q) mcycle_q   <= mcycle_q + 64'd1;
      if (!inh_ir_q) minstret_q <= minstret_q + {62'h0, instret_inc_i} - {63'h0, instret_dec_i};

      if (trap_i) begin
        mepc_q        <= {trap_pc_i[31:1], 1'b0};
        mcause_irq_q  <= trap_irq_i;
        mcause_code_q <= trap_cause_i;
        mtval_q       <= trap_tval_i;
        mpie_q        <= mie_q;
        mie_q         <= 1'b0;
      end else if (mret_i) begin
        mie_q  <= mpie_q;
        mpie_q <= 1'b1;
      end else if (wr_i) begin
        unique case (addr_i)
          12'h300: begin mie_q <= wval[3]; mpie_q <= wval[7]; end
          12'h304: mie_r_q <= {wval[11], 3'b000, wval[7], 3'b000, wval[3], 3'b000};
          12'h305: begin mtvec_base_q <= wval[31:2]; mtvec_mode_q <= wval[0]; end
          12'h320: begin inh_cy_q <= wval[0]; inh_ir_q <= wval[2]; end
          12'h340: mscratch_q <= wval;
          12'h341: mepc_q <= {wval[31:1], 1'b0};
          12'h342: begin mcause_irq_q <= wval[31]; mcause_code_q <= wval[4:0]; end
          12'h343: mtval_q <= wval;
          12'hB00: mcycle_q   <= {mcycle_q[63:32], wval};
          12'hB80: mcycle_q   <= {wval, mcycle_q[31:0]};
          12'hB02: minstret_q <= {minstret_q[63:32], wval};
          12'hB82: minstret_q <= {wval, minstret_q[31:0]};
          default: ;   // read-only / WARL-ignored (misa, mip, ids)
        endcase
      end
    end
  end

endmodule
