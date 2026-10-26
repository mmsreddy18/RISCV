// -----------------------------------------------------------------------------
// tb_pw.sv : minimal testbench for the power run (post-implementation functional simulation + SAIF).
//   Instantiates the wrapper named by the macro DUT_MOD (set it as a Verilog define on sim_1, e.g. DUT_MOD=rv32imc_pw_cfgD).
//   The program is already inside the memories (power-up contents), so nothing is loaded here.
//   Prints PASS/FAIL, total cycles, and the cycles between the ROI markers; ends the simulation on tohost.
//   Tcl for the activity file:  open_saif x.saif; log_saif [get_objects -r /tb_pw/dut/*]; run all; close_saif
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`ifndef DUT_MOD
  `define DUT_MOD rv32imc_pw_cfgD
`endif
module tb_pw;
  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;                       // 100 MHz in the simulation; power is later scaled to the real clock
  logic        tohost_v, putc_v, roi_s, roi_e, retire, trap;
  logic [31:0] tohost;
  logic [7:0]  putc;
  `DUT_MOD dut (.clk_i(clk), .rst_ni(rst_n), .boot_addr_i(32'h0),
    .tohost_valid_o(tohost_v), .tohost_o(tohost), .putchar_valid_o(putc_v), .putchar_o(putc),
    .roi_start_o(roi_s), .roi_stop_o(roi_e), .retire_o(retire), .trap_o(trap));
  initial begin repeat (5) @(posedge clk); @(negedge clk); rst_n = 1'b1; end
  longint unsigned cyc = 0, roi_cyc = 0;
  bit in_roi = 1'b0;
  always @(posedge clk) if (rst_n) begin
    cyc <= cyc + 1;
    if (roi_s) in_roi <= 1'b1;
    if (roi_e) in_roi <= 1'b0;
    if (in_roi) roi_cyc <= roi_cyc + 1;
    if (tohost_v) begin
      if (tohost == 32'd1) $display("TB_PW: PASS cycles=%0d roi_cycles=%0d", cyc, roi_cyc);
      else                 $display("TB_PW: FAIL tohost=0x%08x", tohost);
      $finish;
    end
    if (cyc > 5_000_000) begin $display("TB_PW: TIMEOUT"); $finish; end
  end
endmodule
