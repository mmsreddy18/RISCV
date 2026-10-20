// -----------------------------------------------------------------------------
// rv_c_decoder.sv : RV32C -> RV32I/M expander (combinational)
//   * Covers every RV32C integer instruction (no F/D compressed forms).
//   * On an illegal 16-bit encoding, instr_o is 32'h0, which the main decoder
//     also rejects as illegal (opcode 7'b0000000 is unused).
// -----------------------------------------------------------------------------
module rv_c_decoder (
  input  logic [15:0] instr_i,
  output logic [31:0] instr_o,
  output logic        illegal_o
);

  // 32-bit encoding helpers ---------------------------------------------------
  function automatic logic [31:0] enc_i(input logic [11:0] imm, input logic [4:0] rs1,
                                        input logic [2:0] f3,   input logic [4:0] rd,
                                        input logic [6:0] opc);
    return {imm, rs1, f3, rd, opc};
  endfunction

  function automatic logic [31:0] enc_r(input logic [6:0] f7, input logic [4:0] rs2,
                                        input logic [4:0] rs1, input logic [2:0] f3,
                                        input logic [4:0] rd,  input logic [6:0] opc);
    return {f7, rs2, rs1, f3, rd, opc};
  endfunction

  function automatic logic [31:0] enc_s(input logic [11:0] imm, input logic [4:0] rs2,
                                        input logic [4:0] rs1, input logic [2:0] f3,
                                        input logic [6:0] opc);
    return {imm[11:5], rs2, rs1, f3, imm[4:0], opc};
  endfunction

  function automatic logic [31:0] enc_b(input logic [12:0] imm, input logic [4:0] rs2,
                                        input logic [4:0] rs1, input logic [2:0] f3,
                                        input logic [6:0] opc);
    return {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], opc};
  endfunction

  function automatic logic [31:0] enc_j(input logic [20:0] imm, input logic [4:0] rd,
                                        input logic [6:0] opc);
    return {imm[20], imm[10:1], imm[11], imm[19:12], rd, opc};
  endfunction

  // Field helpers -------------------------------------------------------------
  logic [4:0] rd_rs1;      // full 5-bit rd/rs1  (instr[11:7])
  logic [4:0] rs2_full;    // full 5-bit rs2     (instr[6:2])
  logic [4:0] rd_p;        // rd'  (instr[4:2])  -> x8..x15
  logic [4:0] rs1_p;       // rs1' (instr[9:7])  -> x8..x15
  logic [4:0] rs2_p;       // rs2' (instr[4:2])  -> x8..x15
  logic [5:0] imm6;        // {instr[12], instr[6:2]}

  assign rd_rs1   = instr_i[11:7];
  assign rs2_full = instr_i[6:2];
  assign rd_p     = {2'b01, instr_i[4:2]};
  assign rs1_p    = {2'b01, instr_i[9:7]};
  assign rs2_p    = {2'b01, instr_i[4:2]};
  assign imm6     = {instr_i[12], instr_i[6:2]};

  logic [11:0] imm12_sext6;
  assign imm12_sext6 = {{6{imm6[5]}}, imm6};

  always_comb begin
    illegal_o = 1'b0;
    instr_o   = 32'h0;

    unique case (instr_i[1:0])
      // ------------------------------------------------------------------ Q0
      2'b00: begin
        unique case (instr_i[15:13])
          3'b000: begin // C.ADDI4SPN -> addi rd', x2, nzuimm
            instr_o = enc_i({2'b00, instr_i[10:7], instr_i[12:11], instr_i[5], instr_i[6], 2'b00},
                            5'd2, 3'b000, rd_p, 7'b0010011);
            if (instr_i[12:5] == 8'b0) illegal_o = 1'b1;
          end
          3'b010: begin // C.LW -> lw rd', off(rs1')
            instr_o = enc_i({5'b0, instr_i[5], instr_i[12:10], instr_i[6], 2'b00},
                            rs1_p, 3'b010, rd_p, 7'b0000011);
          end
          3'b110: begin // C.SW -> sw rs2', off(rs1')
            instr_o = enc_s({5'b0, instr_i[5], instr_i[12:10], instr_i[6], 2'b00},
                            rs2_p, rs1_p, 3'b010, 7'b0100011);
          end
          default: illegal_o = 1'b1; // FP loads/stores, reserved
        endcase
      end

      // ------------------------------------------------------------------ Q1
      2'b01: begin
        unique case (instr_i[15:13])
          3'b000: begin // C.ADDI / C.NOP -> addi rd, rd, imm
            instr_o = enc_i(imm12_sext6, rd_rs1, 3'b000, rd_rs1, 7'b0010011);
          end
          3'b001: begin // C.JAL -> jal x1, off
            instr_o = enc_j({{9{instr_i[12]}}, instr_i[12], instr_i[8], instr_i[10:9], instr_i[6],
                             instr_i[7], instr_i[2], instr_i[11], instr_i[5:3], 1'b0},
                            5'd1, 7'b1101111);
          end
          3'b010: begin // C.LI -> addi rd, x0, imm
            instr_o = enc_i(imm12_sext6, 5'd0, 3'b000, rd_rs1, 7'b0010011);
          end
          3'b011: begin
            if (rd_rs1 == 5'd2) begin // C.ADDI16SP -> addi x2, x2, nzimm
              instr_o = enc_i({{3{instr_i[12]}}, instr_i[4:3], instr_i[5], instr_i[2], instr_i[6], 4'b0},
                              5'd2, 3'b000, 5'd2, 7'b0010011);
              if ({instr_i[12], instr_i[6:2]} == 6'b0) illegal_o = 1'b1;
            end else begin            // C.LUI -> lui rd, nzimm
              instr_o = {{14{instr_i[12]}}, instr_i[12], instr_i[6:2], rd_rs1, 7'b0110111};
              if ({instr_i[12], instr_i[6:2]} == 6'b0) illegal_o = 1'b1;
            end
          end
          3'b100: begin
            unique case (instr_i[11:10])
              2'b00: begin // C.SRLI
                instr_o = enc_i({7'b0000000, instr_i[6:2]}, rs1_p, 3'b101, rs1_p, 7'b0010011);
                if (instr_i[12]) illegal_o = 1'b1; // shamt[5] must be 0 on RV32
              end
              2'b01: begin // C.SRAI
                instr_o = enc_i({7'b0100000, instr_i[6:2]}, rs1_p, 3'b101, rs1_p, 7'b0010011);
                if (instr_i[12]) illegal_o = 1'b1;
              end
              2'b10: begin // C.ANDI
                instr_o = enc_i(imm12_sext6, rs1_p, 3'b111, rs1_p, 7'b0010011);
              end
              2'b11: begin
                if (instr_i[12]) begin
                  illegal_o = 1'b1; // SUBW/ADDW are RV64 only
                end else begin
                  unique case (instr_i[6:5])
                    2'b00: instr_o = enc_r(7'b0100000, rs2_p, rs1_p, 3'b000, rs1_p, 7'b0110011); // C.SUB
                    2'b01: instr_o = enc_r(7'b0000000, rs2_p, rs1_p, 3'b100, rs1_p, 7'b0110011); // C.XOR
                    2'b10: instr_o = enc_r(7'b0000000, rs2_p, rs1_p, 3'b110, rs1_p, 7'b0110011); // C.OR
                    2'b11: instr_o = enc_r(7'b0000000, rs2_p, rs1_p, 3'b111, rs1_p, 7'b0110011); // C.AND
                  endcase
                end
              end
            endcase
          end
          3'b101: begin // C.J -> jal x0, off
            instr_o = enc_j({{9{instr_i[12]}}, instr_i[12], instr_i[8], instr_i[10:9], instr_i[6],
                             instr_i[7], instr_i[2], instr_i[11], instr_i[5:3], 1'b0},
                            5'd0, 7'b1101111);
          end
          3'b110, 3'b111: begin // C.BEQZ / C.BNEZ -> beq/bne rs1', x0, off
            instr_o = enc_b({{4{instr_i[12]}}, instr_i[12], instr_i[6:5], instr_i[2],
                             instr_i[11:10], instr_i[4:3], 1'b0},
                            5'd0, rs1_p, {2'b00, instr_i[13]}, 7'b1100011);
          end
        endcase
      end

      // ------------------------------------------------------------------ Q2
      2'b10: begin
        unique case (instr_i[15:13])
          3'b000: begin // C.SLLI -> slli rd, rd, shamt
            instr_o = enc_i({7'b0000000, instr_i[6:2]}, rd_rs1, 3'b001, rd_rs1, 7'b0010011);
            if (instr_i[12]) illegal_o = 1'b1;
          end
          3'b010: begin // C.LWSP -> lw rd, off(x2)
            instr_o = enc_i({4'b0, instr_i[3:2], instr_i[12], instr_i[6:4], 2'b00},
                            5'd2, 3'b010, rd_rs1, 7'b0000011);
            if (rd_rs1 == 5'd0) illegal_o = 1'b1;
          end
          3'b100: begin
            if (!instr_i[12]) begin
              if (rs2_full == 5'd0) begin // C.JR -> jalr x0, 0(rs1)
                instr_o = enc_i(12'b0, rd_rs1, 3'b000, 5'd0, 7'b1100111);
                if (rd_rs1 == 5'd0) illegal_o = 1'b1;
              end else begin               // C.MV -> add rd, x0, rs2
                instr_o = enc_r(7'b0000000, rs2_full, 5'd0, 3'b000, rd_rs1, 7'b0110011);
              end
            end else begin
              if (rs2_full == 5'd0) begin
                if (rd_rs1 == 5'd0) begin   // C.EBREAK
                  instr_o = 32'h0010_0073;
                end else begin              // C.JALR -> jalr x1, 0(rs1)
                  instr_o = enc_i(12'b0, rd_rs1, 3'b000, 5'd1, 7'b1100111);
                end
              end else begin                // C.ADD -> add rd, rd, rs2
                instr_o = enc_r(7'b0000000, rs2_full, rd_rs1, 3'b000, rd_rs1, 7'b0110011);
              end
            end
          end
          3'b110: begin // C.SWSP -> sw rs2, off(x2)
            instr_o = enc_s({4'b0, instr_i[8:7], instr_i[12:9], 2'b00},
                            rs2_full, 5'd2, 3'b010, 7'b0100011);
          end
          default: illegal_o = 1'b1; // FP / reserved
        endcase
      end

      default: begin // 2'b11 : not a compressed instruction
        illegal_o = 1'b1;
      end
    endcase

    if (illegal_o) instr_o = 32'h0;
  end

endmodule
