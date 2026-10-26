// Synthesis wrapper, configuration D: BP_ENABLE=1 ZICSR=1 BTB 8 entries, BHT 16 counters, RAS 2 entries.
// Sizes are hard-coded here so Vivado does not depend on top-level generics. Set this file's module as the top.
module rv32imc_sys_cfgD (
  input  logic        clk_i, rst_ni,
  input  logic [31:0] boot_addr_i,
  output logic        tohost_valid_o,
  output logic [31:0] tohost_o,
  output logic        putchar_valid_o,
  output logic [7:0]  putchar_o,
  output logic        roi_start_o, roi_stop_o, retire_o, trap_o
);
  rv32imc_sys #(.BP_ENABLE(1'b1), .ZICSR(1'b1), .BTB_N(8), .BTB_W(3), .BHT_N(16), .BHT_W(4),
                .RAS_N(2), .RAS_W(1)) u_sys (.*);
endmodule
