// -----------------------------------------------------------------------------
// tb_soc.sv : testbench for rv_soc (core + pulp obi_xbar + SRAM + ROM + MMIO)
//   Plusargs: +hex=<sram image> +rom=<rom image> +maxcyc=<n>.  tohost 1 = PASS, (n<<1)|1 = FAIL n.
//   Counts cycles inside the ROI (stores to MMIO 0x10000008 / 0x1000000C) like tb_core.
// -----------------------------------------------------------------------------

module tb_soc;
  parameter bit          SRAM_STALL = 1'b0;
  parameter bit          SPLIT_MEM  = 1'b1;
  parameter int unsigned SRAM_CUTS  = 0;
  parameter bit          FAST_REDIRECT = 1'b0;
  parameter bit          BP_ENABLE  = 1'b1;
  parameter bit          OBI_STRICT_REQ = 1'b1;
  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;
  logic        tohost_v, putc_v, roi_s, roi_e, retire, trap;
  logic [31:0] tohost;
  logic [7:0]  putc;
  rv_soc #(.SRAM_STALL(SRAM_STALL), .SRAM_CUTS(SRAM_CUTS), .SPLIT_MEM(SPLIT_MEM), .FAST_REDIRECT(FAST_REDIRECT),
           .BP_ENABLE(BP_ENABLE), .OBI_STRICT_REQ(OBI_STRICT_REQ)) dut (
    .clk_i(clk), .rst_ni(rst_n), .boot_addr_i(32'h0004_0000),
    .tohost_valid_o(tohost_v), .tohost_o(tohost), .putchar_valid_o(putc_v), .putchar_o(putc),
    .roi_start_o(roi_s), .roi_stop_o(roi_e), .retire_o(retire), .trap_o(trap));

  bit trace = 1'b0;
  initial if ($test$plusargs("trace")) trace = 1'b1;
  always @(posedge clk) if (trace && rst_n) begin
    if (dut.instr_req && dut.instr_gnt) $display("%0d I %08x", cyc, dut.instr_addr);
    if (dut.data_req && dut.data_gnt)   $display("%0d D %08x we=%0d be=%x wd=%08x", cyc, dut.data_addr, dut.data_we, dut.data_be, dut.data_wdata);
    if (cyc >= 250 && cyc < 262) $display("%0d ST ireq=%b igr=%b iadr=%08x irv=%b | dreq=%b dgr=%b drv=%b", cyc, dut.instr_req, dut.instr_gnt, dut.instr_addr, dut.instr_rvalid, dut.data_req, dut.data_gnt, dut.data_rvalid);
    if (dut.data_rvalid)  $display("%0d   Dresp rd=%08x err=%0d", cyc, dut.data_rdata, dut.data_err);
  end
  longint unsigned cyc = 0, roi_cyc = 0, roi_ret = 0, ret = 0, traps = 0;
  bit in_roi = 1'b0, seen_roi = 1'b0;
  int maxcyc = 50_000_000;
  bit fin = 1'b0; int fin_cnt = 0, fd; string dumpfile = "";
  initial begin
    void'($value$plusargs("maxcyc=%d", maxcyc));
    void'($value$plusargs("dump=%s", dumpfile));
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end
  always @(posedge clk) if (rst_n) begin
    cyc <= cyc + 1;
    if (retire) ret <= ret + 1;
    if (trap) traps <= traps + 1;
    if (roi_s) begin in_roi <= 1'b1; seen_roi <= 1'b1; end
    if (roi_e) in_roi <= 1'b0;
    if (in_roi) begin roi_cyc <= roi_cyc + 1; if (retire) roi_ret <= roi_ret + 1; end
    if (putc_v) $write("%c", putc);
    if (tohost_v && !fin) begin
      fin <= 1'b1; fin_cnt <= 0;
      if (tohost == 32'd1) $display("TB: PASS  cycles=%0d retired=%0d roi_cycles=%0d roi_retired=%0d", cyc, ret, roi_cyc, roi_ret);
      else                 $display("TB: FAIL  tohost=0x%08x (test #%0d)", tohost, tohost >> 1);
    end
    if (fin) begin
      fin_cnt <= fin_cnt + 1;
      if (fin_cnt == 12) begin
        if (dumpfile != "") begin
          fd = $fopen(dumpfile, "w");
          for (int i = 1; i < 32; i++) $fdisplay(fd, "x%0d %08x", i, dut.u_core.u_rf.regs_q[i]);
          for (int i = 0; i < 256; i++) $fdisplay(fd, "m%08x %08x", 32'h4000 + 4*i, dut.u_itcm.u_arr.mem[32'h4000/4 + i]);
          $fclose(fd);
        end
        $finish;
      end
    end
    if (cyc > maxcyc) begin $display("TB: TIMEOUT after %0d cycles (retired=%0d)", cyc, ret); $finish; end
  end
endmodule
