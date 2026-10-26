// Power-run wrapper, configuration B: same sizes as rv32imc_sys_cfgB, with the 1-iteration CoreMark image loaded
// into both memories as power-up contents (the .hex files are the ones in sim_pw/). Used for the post-implementation
// simulation that produces the SAIF activity file.
module rv32imc_pw_cfgB #(
  parameter string IMEM_INIT = "C:/Users/91630/Projects/RV32IMC/sim_pw/cm1.imem.hex",
  parameter string DMEM_INIT = "C:/Users/91630/Projects/RV32IMC/sim_pw/cm1.dmem.hex"
) (
  input  logic        clk_i, rst_ni,
  input  logic [31:0] boot_addr_i,
  output logic        tohost_valid_o,
  output logic [31:0] tohost_o,
  output logic        putchar_valid_o,
  output logic [7:0]  putchar_o,
  output logic        roi_start_o, roi_stop_o, retire_o, trap_o
);
  rv32imc_sys #(.BP_ENABLE(1'b1), .ZICSR(1'b1), .BTB_N(16), .BTB_W(4), .BHT_N(64), .BHT_W(6),
                .RAS_N(8), .RAS_W(3), .IMEM_INIT(IMEM_INIT), .DMEM_INIT(DMEM_INIT)) u_sys (.*);
endmodule
