// -----------------------------------------------------------------------------
// tb_sys.sv : testbench for rv32imc_sys (core + separate instruction / data memory, OBI)
//   Program images (one 32-bit hex word per line, word 0 first):
//     +imem=<file>   loaded into the instruction memory      +dmem=<file>  loaded into the data memory
//   Other plusargs: +maxcyc=<n>  +trace=1 (print every bus transfer)
//   Result: the program stores to the MMIO tohost register: 1 = PASS, (n<<1)|1 = FAIL test n.
//   Counts cycles/instructions between the ROI markers (stores to MMIO+8 / MMIO+0xC), like tb_core.
//   The OBI protocol checker (verif/obi_checker.sv) watches both core ports.
//   Generics: BP_ENABLE, ZICSR, MEM_STALL (random wait states on all memories).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_sys #(
  parameter bit BP_ENABLE = 1'b1,
  parameter bit ZICSR     = 1'b1,
  parameter bit MEM_STALL = 1'b0,
  parameter int BTB_W = 4, BHT_W = 6, RAS_W = 3          // log2 of BTB entries / BHT counters / return-stack entries
);
  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;
  logic        tohost_v, putc_v, roi_s, roi_e, retire, trap;
  logic [31:0] tohost;
  logic [7:0]  putc;

  rv32imc_sys #(.BP_ENABLE(BP_ENABLE), .ZICSR(ZICSR), .MEM_STALL(MEM_STALL),
                .BTB_N(1 << BTB_W), .BTB_W(BTB_W), .BHT_N(1 << BHT_W), .BHT_W(BHT_W), .RAS_N(1 << RAS_W), .RAS_W(RAS_W)) dut (
    .clk_i(clk), .rst_ni(rst_n), .boot_addr_i(32'h0000_0000),
    .tohost_valid_o(tohost_v), .tohost_o(tohost), .putchar_valid_o(putc_v), .putchar_o(putc),
    .roi_start_o(roi_s), .roi_stop_o(roi_e), .retire_o(retire), .trap_o(trap));

  // protocol checkers on the two core ports
  obi_checker #(.NAME("instr"), .DATA(1'b0), .FATAL(1'b0)) u_obi_i (
    .clk_i(clk), .rst_ni(rst_n), .req_i(dut.instr_req), .gnt_i(dut.instr_gnt), .addr_i(dut.instr_addr),
    .we_i(1'b0), .be_i(4'b1111), .wdata_i(32'h0), .rvalid_i(dut.instr_rvalid));
  obi_checker #(.NAME("data"), .DATA(1'b1), .FATAL(1'b0)) u_obi_d (
    .clk_i(clk), .rst_ni(rst_n), .req_i(dut.data_req), .gnt_i(dut.data_gnt), .addr_i(dut.data_addr),
    .we_i(dut.data_we), .be_i(dut.data_be), .wdata_i(dut.data_wdata), .rvalid_i(dut.data_rvalid));

  // load the program images (after the memories' own power-up initialisation at time 0)
  string f_imem, f_dmem;
  initial begin
    #1;
    if ($value$plusargs("imem=%s", f_imem)) begin
      $readmemh(f_imem, dut.u_imem.u_bram.mem);
      $display("TB: loaded instruction memory from %s", f_imem);
    end
    if ($value$plusargs("dmem=%s", f_dmem)) begin
      $readmemh(f_dmem, dut.u_dmem.u_bram.mem);
      $display("TB: loaded data memory from %s", f_dmem);
    end
  end

  int trace = 0;
  int maxcyc = 50_000_000;
  initial begin
    void'($value$plusargs("trace=%d", trace));
    void'($value$plusargs("maxcyc=%d", maxcyc));
    repeat (5) @(posedge clk);
    @(negedge clk);              // release reset away from the rising edge: same result in every simulator
    rst_n = 1'b1;
  end

  longint unsigned cyc = 0, roi_cyc = 0, roi_ret = 0, ret = 0, traps = 0;
  bit in_roi = 1'b0, fin = 1'b0;
  int fin_cnt = 0;
  always @(posedge clk) if (rst_n) begin
    cyc <= cyc + 1;
    if (trace != 0) begin
      if (dut.instr_req && dut.instr_gnt) $display("%0d I %08x", cyc, dut.instr_addr);
      if (dut.data_req && dut.data_gnt)   $display("%0d D %08x we=%0d be=%x wd=%08x", cyc, dut.data_addr, dut.data_we, dut.data_be, dut.data_wdata);
    end
    if (retire) ret <= ret + 1;
    if (trap) traps <= traps + 1;
    if (roi_s) in_roi <= 1'b1;
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
      if (fin_cnt == 12) $finish;
    end
    if (cyc > maxcyc) begin $display("TB: TIMEOUT after %0d cycles (retired=%0d)", cyc, ret); $finish; end
  end
endmodule
