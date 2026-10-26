// Synthesis wrapper, configuration B: BP_ENABLE=1 ZICSR=1 BTB 16 entries, BHT 64 counters, RAS 8 entries.
// Sizes are hard-coded here so Vivado does not depend on top-level generics. Set this file's module as the top.
module rv32imc_sys_cfgB (
  input  logic        clk_i, rst_ni,
  input  logic [31:0] boot_addr_i,
  output logic        tohost_valid_o,
  output logic [31:0] tohost_o,
  output logic        putchar_valid_o,
  output logic [7:0]  putchar_o,
  output logic        roi_start_o, roi_stop_o, retire_o, trap_o
);
  rv32imc_sys #(.BP_ENABLE(1'b1), .ZICSR(1'b1), .BTB_N(16), .BTB_W(4), .BHT_N(64), .BHT_W(6),
                .RAS_N(8), .RAS_W(3)) u_sys (.*);
endmodule
