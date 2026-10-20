// -----------------------------------------------------------------------------
// rv_core.sv : 4-stage RV32IMC core (IF / ID / EX / WB), CV32E40P-style
//
//   IF  rv_fetch      : prefetch FIFO + RVC aligner/expander  -> IF/ID register
//   ID  decode, regfile read, forwarding, BRANCH/JUMP RESOLUTION. Fetch has already
//       followed a prediction (BTB/BHT/RAS); ID only redirects IF on a misprediction.
//   EX  ALU, MUL/DIV, load/store address + data-port request  (multi-cycle capable)
//   WB  load-data return (rvalid), regfile write
//
// Hazard handling
//   * Forwarding into ID (operands are final when they enter EX):
//        EX result (ALU/MUL/DIV, combinational)  >  WB result (incl. load data)
//        > regfile.  So EX never needs its own forwarding muxes.
//   * Load-use: one bubble (a load in EX and a consumer in ID -> ID holds).
//   * Branch/jump mispredicted (direction, target or type) in ID: IF/ID flushed +
//     prefetch FIFO flushed, fetch restarts at the correct address.
//   * Multi-cycle EX (mul[h*], div, waiting for data gnt): EX holds, ID/IF hold,
//     a bubble enters WB.
//   * WB waiting for data rvalid: whole pipeline freezes.
//
// Zicsr + machine-mode traps (rv_csr)
//   * CSR instructions execute in EX (read = ex_result, write when leaving EX).
//   * Exceptions from ID (illegal incl. bad CSR access, ecall, ebreak), mret and
//     interrupts are taken at ID "issue": the instruction becomes a bubble, older
//     instructions in EX/WB complete, fetch is redirected to mtvec / mepc.
//   * Misaligned load/store is detected in EX from the address, before any bus
//     request, and traps from EX (the younger ID instruction is squashed).
//   * Interrupts are taken before the instruction in ID (mepc = its pc).
//   * An instruction in ID that may trap / mret / see an interrupt waits while EX
//     holds a CSR instruction, so it sees the final CSR state (1-cycle hold).
// Not implemented: Zifencei (fence.i is illegal), bus access faults (no error
// signal on the OBI-style ports), instruction-address-misaligned (impossible with C).
// -----------------------------------------------------------------------------
module rv_core
  import rv_pkg::*;
#(
  parameter int unsigned FETCH_DEPTH   = 4,
  parameter bit          FAST_REDIRECT = 1'b0,  // see rv_fetch.sv
  // branch predictor (rv_npc: BTB + BHT + RAS). BP_ENABLE=0 gives the old
  // "resolve every taken branch in ID" behaviour.
  parameter bit          BP_ENABLE  = 1'b1,
  parameter int unsigned BTB_N      = 16,
  parameter int unsigned BTB_W      = 4,
  parameter int unsigned BHT_N      = 64,
  parameter int unsigned BHT_W      = 6,
  parameter int unsigned RAS_N      = 8,
  parameter int unsigned RAS_W      = 3,
  parameter bit          GSHARE     = 1'b0,
  // ZICSR=0: no CSR file / traps / interrupts; ecall, ebreak, CSR ops, mret and illegal
  // instructions are NOPs that only raise the status pins (original RV32IMC behaviour).
  parameter bit          ZICSR      = 1'b1,
  // 1: data_req_o never depends combinationally on data_gnt_i / data_rvalid_i (OBI R-21.1). A
  //    memory access issues only after the previous access's response has been received.
  //    0: the request may issue in the same cycle as the previous response (old behaviour,
  //    faster back-to-back accesses, but violates R-21.1).
  parameter bit          OBI_STRICT_REQ = 1'b1,
  parameter logic [31:0] MTVEC_RESET = 32'h0000_0000
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [31:0] boot_addr_i,
  input  logic [31:0] hart_id_i,

  // Interrupt request lines (levels)
  input  logic        irq_software_i,
  input  logic        irq_timer_i,
  input  logic        irq_external_i,

  // Instruction port (OBI-style)
  output logic        instr_req_o,
  input  logic        instr_gnt_i,
  output logic [31:0] instr_addr_o,
  input  logic        instr_rvalid_i,
  input  logic [31:0] instr_rdata_i,
  input  logic        instr_err_i,     // OBI err (valid with rvalid): instruction access fault; ignored if ZICSR=0

  // Data port (OBI-style)
  output logic        data_req_o,
  input  logic        data_gnt_i,
  output logic [31:0] data_addr_o,
  output logic        data_we_o,
  output logic [3:0]  data_be_o,
  output logic [31:0] data_wdata_o,
  input  logic        data_rvalid_i,
  input  logic [31:0] data_rdata_i,
  input  logic        data_err_i,      // OBI err (valid with rvalid): load/store access fault; ignored if ZICSR=0

  // Status / debug (1-cycle pulses)
  output logic        retire_o,        // an instruction completed WB
  output logic        ecall_o,         // ecall taken (trap) from ID
  output logic        ebreak_o,
  output logic        illegal_o,       // illegal instruction / illegal CSR access trap
  output logic        trap_o,          // any trap or interrupt taken
  output logic        mret_o
);

  // ===========================================================================
  // Forward declarations
  // ===========================================================================
  logic wb_stall, ex_en, ex_complete, ex_go, ex_free;
  logic id_issue, id_go, if_id_ready, redirect;
  logic ex_trap, take_irq, take_exc, take_mret, wb_trap;
  logic [31:0] redirect_pc;
  logic        br_res_valid, br_res_taken, br_res_cond, br_res_call, br_res_ret;
  logic [31:0] br_res_addr, br_res_target;

  // ===========================================================================
  // IF
  // ===========================================================================
  logic        f_valid, f_comp;
  logic [31:0] f_instr, f_pc, f_ptgt;
  logic        f_pt, f_pcall, f_pret, f_err, f_err_hi;

  rv_fetch #(
    .DEPTH(FETCH_DEPTH), .FAST_REDIRECT(FAST_REDIRECT),
    .BP_ENABLE(BP_ENABLE), .BTB_N(BTB_N), .BTB_W(BTB_W), .BHT_N(BHT_N), .BHT_W(BHT_W),
    .RAS_N(RAS_N), .RAS_W(RAS_W), .GSHARE(GSHARE)
  ) u_fetch (
    .clk_i, .rst_ni, .boot_addr_i,
    .redirect_i      (redirect),
    .redirect_pc_i   (redirect_pc),
    .res_valid_i     (br_res_valid),
    .res_addr_i      (br_res_addr),
    .res_taken_i     (br_res_taken),
    .res_target_i    (br_res_target),
    .res_cond_i      (br_res_cond),
    .res_call_i      (br_res_call),
    .res_ret_i       (br_res_ret),
    .instr_req_o, .instr_gnt_i, .instr_addr_o, .instr_rvalid_i, .instr_rdata_i, .instr_err_i,
    .instr_valid_o   (f_valid),
    .instr_ready_i   (if_id_ready),
    .instr_o         (f_instr),
    .pc_o            (f_pc),
    .is_compressed_o (f_comp),
    .pred_taken_o    (f_pt),
    .pred_target_o   (f_ptgt),
    .pred_call_o     (f_pcall),
    .pred_ret_o      (f_pret),
    .instr_err_o     (f_err),
    .instr_err_hi_o  (f_err_hi)
  );

  // IF/ID register
  logic        id_valid_q, id_comp_q, id_pt_q, id_pcall_q, id_pret_q, id_ferr_q, id_ferr_hi_q, id_ferr;
  logic [31:0] id_instr_q, id_pc_q, id_ptgt_q;

  assign if_id_ready = ~id_valid_q | id_go;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      id_valid_q <= 1'b0;
    end else if (redirect) begin
      id_valid_q <= 1'b0;
    end else if (if_id_ready) begin
      id_valid_q <= f_valid;
    end
  end

  always_ff @(posedge clk_i) begin
    if (if_id_ready) begin
      id_instr_q <= f_instr;
      id_pc_q    <= f_pc;
      id_comp_q  <= f_comp;
      id_pt_q    <= f_pt;
      id_ptgt_q  <= f_ptgt;
      id_pcall_q <= f_pcall;
      id_pret_q  <= f_pret;
      id_ferr_q    <= f_err;
      id_ferr_hi_q <= f_err_hi;
    end
  end

  // ===========================================================================
  // ID : decode, register read, forwarding, branch resolution
  // ===========================================================================
  logic [4:0]  id_rs1, id_rs2, id_rd;
  logic        id_use_rs1, id_use_rs2, id_reg_we;
  logic [31:0] id_imm;
  alu_op_e     id_alu_op;
  opa_sel_e    id_opa_sel;
  opb_sel_e    id_opb_sel;
  logic        id_is_branch, id_is_jal, id_is_jalr, id_is_load, id_is_store;
  logic [2:0]  id_f3;
  logic        id_is_mul, id_is_div, id_ecall, id_ebreak, id_illegal, id_is_csr, id_is_mret;
  logic        id_illegal_d, id_is_csr_d, id_is_mret_d;

  rv_decoder u_dec (
    .instr_i     (id_instr_q),
    .rs1_o       (id_rs1),   .rs2_o (id_rs2),   .rd_o (id_rd),
    .use_rs1_o   (id_use_rs1), .use_rs2_o (id_use_rs2),
    .imm_o       (id_imm),
    .alu_op_o    (id_alu_op), .opa_sel_o (id_opa_sel), .opb_sel_o (id_opb_sel),
    .reg_we_o    (id_reg_we),
    .is_branch_o (id_is_branch), .is_jal_o (id_is_jal), .is_jalr_o (id_is_jalr),
    .is_load_o   (id_is_load),   .is_store_o (id_is_store),
    .funct3_o    (id_f3),
    .is_mul_o    (id_is_mul),    .is_div_o (id_is_div),
    .ecall_o     (id_ecall),     .ebreak_o (id_ebreak),
    .is_csr_o    (id_is_csr_d),  .is_mret_o (id_is_mret_d), .illegal_o (id_illegal_d)
  );

  assign id_is_csr  = ZICSR & id_is_csr_d;
  assign id_is_mret = ZICSR & id_is_mret_d;
  assign id_illegal = id_illegal_d | (~ZICSR & (id_is_csr_d | id_is_mret_d));

  // ---- EX / WB state referenced by forwarding (declared here, driven below) --
  logic        ex_valid_q, ex_we_q, ex_load_q, ex_store_q, ex_mul_q, ex_div_q;
  logic        ex_csr_q, ex_csr_wr_q;
  logic [11:0] ex_csr_addr_q;
  logic [31:0] ex_pc_q;
  logic [4:0]  ex_rd_q;
  logic [31:0] ex_a_q, ex_b_q, ex_sdata_q;
  logic [2:0]  ex_f3_q;
  alu_op_e     ex_alu_op_q;
  logic [31:0] ex_result;

  logic        wb_valid_q, wb_we_q, wb_load_q, wb_mem_q;
  logic [4:0]  wb_rd_q;
  logic [2:0]  wb_f3_q;
  logic [1:0]  wb_lsb_q;
  logic [31:0] wb_result_q, wb_wdata, wb_pc_q;

  // ---- register file ----------------------------------------------------------
  logic [31:0] rf_rdata1, rf_rdata2;
  logic        rf_we;

  rv_regfile u_rf (
    .clk_i,
    .we_i     (rf_we),
    .waddr_i  (wb_rd_q),
    .wdata_i  (wb_wdata),
    .raddr1_i (id_rs1), .raddr2_i (id_rs2),
    .rdata1_o (rf_rdata1), .rdata2_o (rf_rdata2)
  );

  // ---- forwarding: EX (combinational result) > WB > regfile --------------------
  logic ex_fwd_ok, wb_fwd_ok;
  assign ex_fwd_ok = ex_valid_q & ex_we_q & (ex_rd_q != 5'd0);
  assign wb_fwd_ok = rf_we;                                   // retiring, writes rd != x0

  logic [31:0] id_rs1_val, id_rs2_val;
  always_comb begin
    if      (ex_fwd_ok && ex_rd_q == id_rs1) id_rs1_val = ex_result;
    else if (wb_fwd_ok && wb_rd_q == id_rs1) id_rs1_val = wb_wdata;
    else                                     id_rs1_val = rf_rdata1;

    if      (ex_fwd_ok && ex_rd_q == id_rs2) id_rs2_val = ex_result;
    else if (wb_fwd_ok && wb_rd_q == id_rs2) id_rs2_val = wb_wdata;
    else                                     id_rs2_val = rf_rdata2;
  end

  // ---- load-use hazard ---------------------------------------------------------
  logic load_use;
  assign load_use = id_valid_q & ex_valid_q & ex_load_q & (ex_rd_q != 5'd0) &
                    ((id_use_rs1 & (id_rs1 == ex_rd_q)) |
                     (id_use_rs2 & (id_rs2 == ex_rd_q)));

  // ---- CSR legality / trap decision in ID ---------------------------------------
  logic        csr_chk_illegal, id_csr_wr, id_csr_illegal, id_exc, csr_busy, irq_pend;
  logic [4:0]  id_exc_cause, irq_cause;
  logic [31:0] mepc, trap_vec, csr_rdata;

  assign id_csr_wr      = (id_f3[1:0] == 2'b01) | (id_rs1 != 5'd0);   // RS/RC with x0/uimm=0 do not write
  assign id_csr_illegal = id_is_csr & csr_chk_illegal;
  assign id_ferr        = ZICSR & id_ferr_q;      // instruction access fault (garbage instruction)
  assign id_exc         = ZICSR & (id_ferr_q | id_illegal | id_csr_illegal | id_ecall | id_ebreak);
  assign id_exc_cause   = id_ferr ? 5'd1 : id_ebreak ? 5'd3 : id_ecall ? 5'd11 : 5'd2;

  // A CSR instruction in EX has not written yet: anything in ID that may trap, mret or
  // take an interrupt must wait one cycle to see the final mstatus/mtvec/mepc.
  assign csr_busy = ex_valid_q & ex_csr_q;

  // ---- ID "go": the instruction leaves ID (to EX, or consumed by a trap/mret) ------
  assign id_go    = id_valid_q & ~load_use & ex_free & ~ex_trap &
                    ~(csr_busy & (id_exc | id_is_mret | irq_pend));
  assign take_irq  = id_go & irq_pend;
  assign take_exc  = id_go & ~irq_pend & id_exc;
  assign take_mret = id_go & ~irq_pend & ~id_exc & id_is_mret;
  assign id_issue  = id_go & ~irq_pend & ~id_exc & ~id_is_mret;   // enters EX

  // ---- branch / jump resolution --------------------------------------------------
  logic br_taken;
  always_comb begin
    unique case (id_f3)
      3'b000:  br_taken = (id_rs1_val == id_rs2_val);
      3'b001:  br_taken = (id_rs1_val != id_rs2_val);
      3'b100:  br_taken = ($signed(id_rs1_val) <  $signed(id_rs2_val));
      3'b101:  br_taken = ($signed(id_rs1_val) >= $signed(id_rs2_val));
      3'b110:  br_taken = (id_rs1_val <  id_rs2_val);
      3'b111:  br_taken = (id_rs1_val >= id_rs2_val);
      default: br_taken = 1'b0;
    endcase
  end

  logic [31:0] jalr_target, pcrel_target;
  assign jalr_target  = (id_rs1_val + id_imm) & 32'hFFFF_FFFE;
  assign pcrel_target = id_pc_q + id_imm;

  // What the instruction really does ...
  logic        act_taken, act_call, act_ret, id_rd_is_ra;
  logic [31:0] act_target, seq_pc;
  assign id_rd_is_ra = (id_rd == 5'd1);
  assign act_taken   = id_is_jal | id_is_jalr | (id_is_branch & br_taken);
  assign act_target  = id_is_jalr ? jalr_target : pcrel_target;
  assign seq_pc      = id_pc_q + (id_comp_q ? 32'd2 : 32'd4);
  // call / return classification as in biRISC-V (link register = x1)
  assign act_ret     = id_is_jalr & (id_rs1 == 5'd1) & (id_imm[11:0] == 12'h000);
  assign act_call    = (id_is_jal | id_is_jalr) & ~act_ret & id_rd_is_ra;

  // ... against what fetch assumed (id_pt_q / id_ptgt_q). A wrong direction, target
  // or call/return type redirects; the type is compared so that the predictor's
  // speculative RAS pointer cannot drift from the real one.
  logic mispredict;
  assign mispredict = id_pt_q ? (~act_taken | (act_target != id_ptgt_q) |
                                 (act_call != id_pcall_q) | (act_ret != id_pret_q))
                              : act_taken;

  logic trap_ev;
  assign trap_ev     = wb_trap | ex_trap | take_irq | take_exc;
  assign redirect    = trap_ev | take_mret | (id_issue & mispredict);
  assign redirect_pc = trap_ev   ? trap_vec :
                       take_mret ? mepc :
                       act_taken ? act_target : seq_pc;

  // predictor training: every branch/jump, once, as it issues
  assign br_res_valid  = id_issue & (id_is_branch | id_is_jal | id_is_jalr);
  assign br_res_addr   = id_pc_q + (id_comp_q ? 32'd0 : 32'd2);   // last halfword
  assign br_res_taken  = act_taken;
  assign br_res_target = act_target;
  assign br_res_cond   = id_is_branch;
  assign br_res_call   = act_call;
  assign br_res_ret    = act_ret;

  // ---- status pulses ---------------------------------------------------------------
  assign ecall_o   = (ZICSR ? take_exc : id_issue) & ~id_ferr & id_ecall;
  assign ebreak_o  = (ZICSR ? take_exc : id_issue) & ~id_ferr & id_ebreak;
  assign illegal_o = (ZICSR ? take_exc : id_issue) & ~id_ferr & (id_illegal | id_csr_illegal);
  assign trap_o    = trap_ev;
  assign mret_o    = take_mret;

  // ---- operand selection ------------------------------------------------------------
  logic [31:0] id_op_a, id_op_b;
  always_comb begin
    unique case (id_opa_sel)
      OPA_RS1: id_op_a = id_rs1_val;
      OPA_PC:  id_op_a = id_pc_q;
      OPA_ZIMM: id_op_a = {27'h0, id_rs1};
      default: id_op_a = 32'h0;
    endcase
    unique case (id_opb_sel)
      OPB_RS2: id_op_b = id_rs2_val;
      OPB_IMM: id_op_b = id_imm;
      default: id_op_b = id_comp_q ? 32'd2 : 32'd4;   // link offset
    endcase
  end

  // ===========================================================================
  // ID/EX register
  // ===========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)      ex_valid_q <= 1'b0;
    else if (wb_trap) ex_valid_q <= 1'b0;          // younger instruction squashed by a load/store access fault
    else if (ex_free) ex_valid_q <= id_issue;
  end

  always_ff @(posedge clk_i) begin
    if (ex_free) begin
      ex_a_q      <= id_op_a;
      ex_b_q      <= id_op_b;
      ex_sdata_q  <= id_rs2_val;
      ex_alu_op_q <= id_alu_op;
      ex_rd_q     <= id_rd;
      ex_we_q     <= id_reg_we;
      ex_load_q   <= id_is_load;
      ex_store_q  <= id_is_store;
      ex_mul_q    <= id_is_mul;
      ex_div_q    <= id_is_div;
      ex_f3_q     <= id_f3;
      ex_pc_q     <= id_pc_q;
      ex_csr_q    <= id_is_csr;
      ex_csr_wr_q <= id_csr_wr;
      ex_csr_addr_q <= id_instr_q[31:20];
    end
  end

  // ===========================================================================
  // EX : ALU, MUL, DIV, memory request
  // ===========================================================================
  logic [31:0] alu_result, mul_result, div_result;
  logic        mul_done, div_done, ex_is_mem;

  rv_alu u_alu (
    .op_i (ex_alu_op_q), .a_i (ex_a_q), .b_i (ex_b_q), .result_o (alu_result)
  );

  rv_mul u_mul (
    .clk_i, .rst_ni,
    .en_i     (ex_en),
    .flush_i  (wb_trap),
    .valid_i  (ex_valid_q & ex_mul_q),
    .funct3_i (ex_f3_q),
    .a_i      (ex_a_q), .b_i (ex_b_q),
    .done_o   (mul_done),
    .result_o (mul_result)
  );

  rv_div u_div (
    .clk_i, .rst_ni,
    .en_i     (ex_en),
    .flush_i  (wb_trap),
    .valid_i  (ex_valid_q & ex_div_q),
    .funct3_i (ex_f3_q),
    .a_i      (ex_a_q), .b_i (ex_b_q),
    .done_o   (div_done),
    .result_o (div_result)
  );

  assign ex_result = ex_csr_q ? csr_rdata :
                     ex_mul_q ? mul_result :
                     ex_div_q ? div_result : alu_result;

  assign ex_is_mem   = ex_load_q | ex_store_q;
  assign ex_en       = ~wb_stall & ~wb_trap;

  // Data port request: issued when EX holds a mem op and WB is not blocking.
  // Misaligned load/store: detected from the address, no bus request, trap from EX.
  logic ex_misalign;
  assign ex_misalign = ZICSR & ex_is_mem & (((ex_f3_q[1:0] == 2'b10) & (alu_result[1:0] != 2'b00)) |
                                    ((ex_f3_q[1:0] == 2'b01) &  alu_result[0]));
  assign ex_trap     = ex_en & ex_valid_q & ex_misalign;

  // OBI_STRICT_REQ: request only from registered state (WB holds no memory op whose response
  // is outstanding), so req does not depend combinationally on rvalid/gnt/err (R-21.1) and a
  // younger access can never be issued before an older access's fault is known (precise).
  logic data_req_ok;
  assign data_req_ok  = OBI_STRICT_REQ ? ~(wb_valid_q & wb_mem_q) : ex_en;
  assign data_req_o   = data_req_ok & ex_valid_q & ex_is_mem & ~ex_misalign;
  assign data_addr_o  = alu_result;
  assign data_we_o    = ex_store_q;

  always_comb begin
    unique case (ex_f3_q[1:0])
      2'b00:   data_be_o = 4'b0001 << alu_result[1:0];
      2'b01:   data_be_o = 4'b0011 << alu_result[1:0];
      default: data_be_o = 4'b1111;
    endcase
    unique case (ex_f3_q[1:0])
      2'b00:   data_wdata_o = {4{ex_sdata_q[7:0]}};
      2'b01:   data_wdata_o = {2{ex_sdata_q[15:0]}};
      default: data_wdata_o = ex_sdata_q;
    endcase
  end

  always_comb begin
    if      (ex_is_mem) ex_complete = (data_req_o & data_gnt_i) | ex_misalign;   // gnt may be high without req (OBI R-3.2.1)
    else if (ex_mul_q)  ex_complete = mul_done;
    else if (ex_div_q)  ex_complete = div_done;
    else                ex_complete = 1'b1;
  end

  assign ex_go   = ex_en & ex_valid_q & ex_complete;       // EX -> WB this cycle
  assign ex_free = ex_en & (~ex_valid_q | ex_complete);    // EX can accept a new op

  // ---- CSR file + trap state ------------------------------------------------------
  logic        ex_go_real;
  logic [1:0]  instret_inc;
  logic [4:0]  trap_cause;
  assign ex_go_real  = ex_go & ~ex_misalign;
  assign instret_inc = {1'b0, ex_go_real} + {1'b0, take_mret};
  assign trap_cause  = wb_trap  ? (wb_load_q ? 5'd5 : 5'd7) :
                       take_irq ? irq_cause :
                       ex_trap  ? (ex_store_q ? 5'd6 : 5'd4) : id_exc_cause;

  if (ZICSR) begin : g_csr
    rv_csr #(.MTVEC_RESET(MTVEC_RESET)) u_csr (
      .clk_i, .rst_ni, .hart_id_i,
      .irq_software_i, .irq_timer_i, .irq_external_i,
      .chk_addr_i    (id_instr_q[31:20]),
      .chk_write_i   (id_csr_wr),
      .chk_illegal_o (csr_chk_illegal),
      .addr_i        (ex_csr_addr_q),
      .op_i          (ex_f3_q[1:0]),
      .wdata_i       (ex_a_q),
      .wr_i          (ex_go & ex_csr_q & ex_csr_wr_q),
      .rdata_o       (csr_rdata),
      .instret_inc_i (instret_inc),
      .instret_dec_i (wb_trap),
      .trap_i        (trap_ev),
      .trap_irq_i    (take_irq),
      .trap_cause_i  (trap_cause),
      .trap_pc_i     (wb_trap ? wb_pc_q : ex_trap ? ex_pc_q : id_pc_q),
      .trap_tval_i   (wb_trap ? wb_result_q : ex_trap ? alu_result :
                      id_ferr ? (id_ferr_hi_q ? id_pc_q + 32'd2 : id_pc_q) : 32'h0),
      .mret_i        (take_mret),
      .mepc_o        (mepc),
      .trap_vec_o    (trap_vec),
      .irq_pending_o (irq_pend),
      .irq_cause_o   (irq_cause)
    );
  end else begin : g_nocsr
    assign csr_chk_illegal = 1'b0;
    assign csr_rdata       = 32'h0;
    assign mepc            = 32'h0;
    assign trap_vec        = 32'h0;
    assign irq_pend        = 1'b0;
    assign irq_cause       = 5'd0;
  end


  // ===========================================================================
  // EX/WB register
  // ===========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)        wb_valid_q <= 1'b0;
    else if (!wb_stall) wb_valid_q <= ex_go & ~ex_misalign;
  end

  always_ff @(posedge clk_i) begin
    if (!wb_stall) begin
      wb_rd_q     <= ex_rd_q;
      wb_we_q     <= ex_we_q;
      wb_load_q   <= ex_load_q;
      wb_mem_q    <= ex_is_mem;
      wb_f3_q     <= ex_f3_q;
      wb_lsb_q    <= alu_result[1:0];
      wb_result_q <= ex_result;
      wb_pc_q     <= ex_pc_q;
    end
  end

  // ===========================================================================
  // WB : load data return + register write
  // ===========================================================================
  assign wb_stall = wb_valid_q & wb_mem_q & ~data_rvalid_i;
  assign wb_trap  = ZICSR & wb_valid_q & wb_mem_q & data_rvalid_i & data_err_i;
  assign retire_o = wb_valid_q & ~wb_stall & ~wb_trap;

  logic [31:0] ld_shifted, ld_data;
  assign ld_shifted = data_rdata_i >> {wb_lsb_q, 3'b000};

  always_comb begin
    unique case (wb_f3_q[1:0])
      2'b00:   ld_data = wb_f3_q[2] ? {24'h0, ld_shifted[7:0]}
                                    : {{24{ld_shifted[7]}}, ld_shifted[7:0]};
      2'b01:   ld_data = wb_f3_q[2] ? {16'h0, ld_shifted[15:0]}
                                    : {{16{ld_shifted[15]}}, ld_shifted[15:0]};
      default: ld_data = ld_shifted;
    endcase
  end

  assign wb_wdata = wb_load_q ? ld_data : wb_result_q;
  assign rf_we    = retire_o & wb_we_q & (wb_rd_q != 5'd0);

endmodule
