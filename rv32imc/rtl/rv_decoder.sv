// -----------------------------------------------------------------------------
// rv_decoder.sv : RV32IM decoder (combinational, operates on a 32-bit instr)
//   SYSTEM: ecall, ebreak, mret, wfi (NOP) and the six Zicsr instructions.
//   fence.i (Zifencei) is still flagged illegal.
// -----------------------------------------------------------------------------
module rv_decoder
  import rv_pkg::*;
(
  input  logic [31:0] instr_i,

  output logic [4:0]  rs1_o,
  output logic [4:0]  rs2_o,
  output logic [4:0]  rd_o,
  output logic        use_rs1_o,     // instruction reads rs1 (hazard detection)
  output logic        use_rs2_o,     // instruction reads rs2
  output logic [31:0] imm_o,

  output alu_op_e     alu_op_o,
  output opa_sel_e    opa_sel_o,
  output opb_sel_e    opb_sel_o,
  output logic        reg_we_o,

  output logic        is_branch_o,
  output logic        is_jal_o,
  output logic        is_jalr_o,
  output logic        is_load_o,
  output logic        is_store_o,
  output logic [2:0]  funct3_o,
  output logic        is_mul_o,
  output logic        is_div_o,

  output logic        ecall_o,
  output logic        ebreak_o,
  output logic        is_csr_o,      // csrrw/rs/rc[i]; f3[1:0] = op, f3[2] = immediate form
  output logic        is_mret_o,
  output logic        illegal_o
);

  logic [6:0] opcode;
  logic [2:0] f3;
  logic [6:0] f7;

  assign opcode = instr_i[6:0];
  assign f3     = instr_i[14:12];
  assign f7     = instr_i[31:25];

  logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  assign imm_i = {{20{instr_i[31]}}, instr_i[31:20]};
  assign imm_s = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
  assign imm_b = {{19{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
  assign imm_u = {instr_i[31:12], 12'b0};
  assign imm_j = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};

  assign rs1_o    = instr_i[19:15];
  assign rs2_o    = instr_i[24:20];
  assign rd_o     = instr_i[11:7];
  assign funct3_o = f3;

  always_comb begin
    use_rs1_o   = 1'b0;
    use_rs2_o   = 1'b0;
    imm_o       = imm_i;
    alu_op_o    = ALU_ADD;
    opa_sel_o   = OPA_RS1;
    opb_sel_o   = OPB_IMM;
    reg_we_o    = 1'b0;
    is_branch_o = 1'b0;
    is_jal_o    = 1'b0;
    is_jalr_o   = 1'b0;
    is_load_o   = 1'b0;
    is_store_o  = 1'b0;
    is_mul_o    = 1'b0;
    is_div_o    = 1'b0;
    ecall_o     = 1'b0;
    ebreak_o    = 1'b0;
    is_csr_o    = 1'b0;
    is_mret_o   = 1'b0;
    illegal_o   = 1'b0;

    unique case (opcode)
      OPC_LUI: begin
        imm_o     = imm_u;
        opa_sel_o = OPA_ZERO;
        reg_we_o  = 1'b1;
      end

      OPC_AUIPC: begin
        imm_o     = imm_u;
        opa_sel_o = OPA_PC;
        reg_we_o  = 1'b1;
      end

      OPC_JAL: begin
        imm_o     = imm_j;
        is_jal_o  = 1'b1;
        opa_sel_o = OPA_PC;
        opb_sel_o = OPB_LINK;
        reg_we_o  = 1'b1;
      end

      OPC_JALR: begin
        use_rs1_o = 1'b1;
        imm_o     = imm_i;
        is_jalr_o = 1'b1;
        opa_sel_o = OPA_PC;
        opb_sel_o = OPB_LINK;
        reg_we_o  = 1'b1;
        if (f3 != 3'b000) illegal_o = 1'b1;
      end

      OPC_BRANCH: begin
        use_rs1_o   = 1'b1;
        use_rs2_o   = 1'b1;
        imm_o       = imm_b;
        is_branch_o = 1'b1;
        if (f3 == 3'b010 || f3 == 3'b011) illegal_o = 1'b1;
      end

      OPC_LOAD: begin
        use_rs1_o = 1'b1;
        imm_o     = imm_i;
        is_load_o = 1'b1;
        reg_we_o  = 1'b1;
        if (!(f3 inside {3'b000, 3'b001, 3'b010, 3'b100, 3'b101})) illegal_o = 1'b1;
      end

      OPC_STORE: begin
        use_rs1_o  = 1'b1;
        use_rs2_o  = 1'b1;
        imm_o      = imm_s;
        is_store_o = 1'b1;
        if (!(f3 inside {3'b000, 3'b001, 3'b010})) illegal_o = 1'b1;
      end

      OPC_OP_IMM: begin
        use_rs1_o = 1'b1;
        imm_o     = imm_i;
        reg_we_o  = 1'b1;
        unique case (f3)
          3'b000: alu_op_o = ALU_ADD;
          3'b010: alu_op_o = ALU_SLT;
          3'b011: alu_op_o = ALU_SLTU;
          3'b100: alu_op_o = ALU_XOR;
          3'b110: alu_op_o = ALU_OR;
          3'b111: alu_op_o = ALU_AND;
          3'b001: begin
            alu_op_o = ALU_SLL;
            if (f7 != 7'b0000000) illegal_o = 1'b1;
          end
          3'b101: begin
            if      (f7 == 7'b0000000) alu_op_o = ALU_SRL;
            else if (f7 == 7'b0100000) alu_op_o = ALU_SRA;
            else                       illegal_o = 1'b1;
          end
        endcase
      end

      OPC_OP: begin
        use_rs1_o = 1'b1;
        use_rs2_o = 1'b1;
        opb_sel_o = OPB_RS2;
        reg_we_o  = 1'b1;
        if (f7 == 7'b0000001) begin            // M extension
          if (f3[2]) is_div_o = 1'b1;
          else       is_mul_o = 1'b1;
        end else if (f7 == 7'b0000000) begin
          unique case (f3)
            3'b000: alu_op_o = ALU_ADD;
            3'b001: alu_op_o = ALU_SLL;
            3'b010: alu_op_o = ALU_SLT;
            3'b011: alu_op_o = ALU_SLTU;
            3'b100: alu_op_o = ALU_XOR;
            3'b101: alu_op_o = ALU_SRL;
            3'b110: alu_op_o = ALU_OR;
            3'b111: alu_op_o = ALU_AND;
          endcase
        end else if (f7 == 7'b0100000) begin
          if      (f3 == 3'b000) alu_op_o = ALU_SUB;
          else if (f3 == 3'b101) alu_op_o = ALU_SRA;
          else                   illegal_o = 1'b1;
        end else begin
          illegal_o = 1'b1;
        end
      end

      OPC_MISC_MEM: begin
        // FENCE is a NOP in this in-order, cache-less core. FENCE.I (f3=001)
        // needs Zifencei and is illegal until that is added.
        if (f3 != 3'b000) illegal_o = 1'b1;
      end

      OPC_SYSTEM: begin
        if (f3 == 3'b000) begin
          if      (instr_i == 32'h0000_0073) ecall_o  = 1'b1;
          else if (instr_i == 32'h0010_0073) ebreak_o = 1'b1;
          else if (instr_i == 32'h3020_0073) is_mret_o = 1'b1;
          else if (instr_i == 32'h1050_0073) ;                 // wfi: NOP
          else                               illegal_o = 1'b1;
        end else if (f3 == 3'b100) begin
          illegal_o = 1'b1;
        end else begin                                         // Zicsr
          is_csr_o  = 1'b1;
          reg_we_o  = 1'b1;
          use_rs1_o = ~f3[2];
          opa_sel_o = f3[2] ? OPA_ZIMM : OPA_RS1;
        end
      end

      default: illegal_o = 1'b1;
    endcase

    // An illegal instruction must have no architectural side effects.
    if (illegal_o) begin
      use_rs1_o   = 1'b0;
      use_rs2_o   = 1'b0;
      reg_we_o    = 1'b0;
      is_branch_o = 1'b0;
      is_jal_o    = 1'b0;
      is_jalr_o   = 1'b0;
      is_load_o   = 1'b0;
      is_store_o  = 1'b0;
      is_mul_o    = 1'b0;
      is_div_o    = 1'b0;
      is_csr_o    = 1'b0;
      is_mret_o   = 1'b0;
    end
  end

endmodule
