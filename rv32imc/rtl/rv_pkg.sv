// -----------------------------------------------------------------------------
// rv_pkg.sv : shared types / constants for the RV32IMC core
// -----------------------------------------------------------------------------
package rv_pkg;

  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND
  } alu_op_e;

  // ALU operand A select
  // OPA_ZIMM = zero-extended rs1 field (CSR immediate forms)
  typedef enum logic [1:0] { OPA_RS1, OPA_PC, OPA_ZERO, OPA_ZIMM } opa_sel_e;
  // ALU operand B select (LINK = 2 or 4, the length of the current instruction)
  typedef enum logic [1:0] { OPB_RS2, OPB_IMM, OPB_LINK } opb_sel_e;

  // Major opcodes (instr[6:0])
  localparam logic [6:0] OPC_LOAD     = 7'b0000011;
  localparam logic [6:0] OPC_MISC_MEM = 7'b0001111;
  localparam logic [6:0] OPC_OP_IMM   = 7'b0010011;
  localparam logic [6:0] OPC_AUIPC    = 7'b0010111;
  localparam logic [6:0] OPC_STORE    = 7'b0100011;
  localparam logic [6:0] OPC_OP       = 7'b0110011;
  localparam logic [6:0] OPC_LUI      = 7'b0110111;
  localparam logic [6:0] OPC_BRANCH   = 7'b1100011;
  localparam logic [6:0] OPC_JALR     = 7'b1100111;
  localparam logic [6:0] OPC_JAL      = 7'b1101111;
  localparam logic [6:0] OPC_SYSTEM   = 7'b1110011;

endpackage
