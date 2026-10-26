// -----------------------------------------------------------------------------
// tb_fetch.sv : stand-alone, self-checking testbench for the fetch unit (rv_fetch)
//
//  What is around the DUT (all modelled here):
//    * an instruction memory with an OBI-style port: req / addr / gnt, then rvalid / rdata later.
//      It can insert random wait states on gnt and random response latency (always in order).
//    * the "decode side": it accepts instructions with a valid/ready handshake; ready can be random
//      (back-pressure), and it can ask for a redirect (a taken branch) to any instruction start.
//
//  How a result is judged (the SCOREBOARD):
//    The testbench builds a program image of mixed 16-bit and 32-bit instructions and therefore
//    KNOWS, for every address where an instruction starts, what 32-bit instruction fetch must deliver
//    (compressed ones in expanded form), and whether it was compressed. For each instruction fetch
//    hands over (valid && ready) the scoreboard checks:   pc, expanded instruction, compressed flag.
//    The expected next PC is pc+2 / pc+4, or the redirect target after a redirect.
//
//  OBI rules checked on the memory port every cycle:
//    * no request while reset is low                        (OBI R-2.1)
//    * a request not granted stays asserted, same address   (OBI R-3.1.1 / R-3.1.2)
//
//  Run:   verif/fetch/run_fetch.sh            (Verilator)   or add the files listed there to Vivado xsim.
//  Plusarg:  +trace=1  prints a cycle-by-cycle table for the first directed test.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_fetch;
  localparam int NIN = 300;      // instructions in the program image
  localparam int HWN = 1024;     // halfwords in the image (4 KiB)

  // ------------------------------------------------------------------ DUT
  logic        clk = 1'b0;
  logic        rst_ni = 1'b0;
  logic [31:0] boot_addr;
  logic        redirect_i;
  logic [31:0] redirect_pc_i;
  logic        instr_req_o, instr_gnt_i, instr_rvalid_i;
  logic [31:0] instr_addr_o, instr_rdata_i;
  logic        instr_valid_o, instr_ready_i, is_compressed_o, instr_err_o, instr_err_hi_o;
  logic [31:0] instr_o, pc_o;

  always #5 clk = ~clk;

  rv_fetch #(.DEPTH(4), .FAST_REDIRECT(1'b0), .BP_ENABLE(1'b0)) dut (
    .clk_i(clk), .rst_ni(rst_ni), .boot_addr_i(boot_addr),
    .redirect_i(redirect_i), .redirect_pc_i(redirect_pc_i),
    .res_valid_i(1'b0), .res_addr_i(32'h0), .res_taken_i(1'b0), .res_target_i(32'h0),
    .res_cond_i(1'b0), .res_call_i(1'b0), .res_ret_i(1'b0),
    .instr_req_o(instr_req_o), .instr_gnt_i(instr_gnt_i), .instr_addr_o(instr_addr_o),
    .instr_rvalid_i(instr_rvalid_i), .instr_rdata_i(instr_rdata_i), .instr_err_i(1'b0),
    .instr_valid_o(instr_valid_o), .instr_ready_i(instr_ready_i), .instr_o(instr_o), .pc_o(pc_o),
    .is_compressed_o(is_compressed_o), .pred_taken_o(), .pred_target_o(), .pred_call_o(), .pred_ret_o(),
    .instr_err_o(instr_err_o), .instr_err_hi_o(instr_err_hi_o)
  );

  // ------------------------------------------------------ random numbers (same in every simulator)
  int unsigned rs = 32'h1234_abcd;
  function int unsigned rnd();
    rs = rs ^ (rs << 13);
    rs = rs ^ (rs >> 17);
    rs = rs ^ (rs << 5);
    return rs;
  endfunction
  function bit pct(input int p);          // true with probability p percent
    int unsigned x;
    x = rnd();
    return (x % 100) < p;
  endfunction

  // --------------------------------------------------------------- program image
  logic [15:0] hw      [HWN];     // the memory contents, halfword by halfword
  logic [31:0] e_instr [HWN];     // expected 32-bit instruction that STARTS at this halfword
  bit          e_comp  [HWN];     // ... and whether it was a 16-bit one
  bit          e_start [HWN];     // an instruction starts here
  int unsigned start_pc [NIN];    // byte address of every instruction start
  int unsigned end_limit_pc;      // near the end of the image: force a jump back

  // pattern used by the directed tests: bit n = 1 -> instruction n is 16-bit, 0 -> 32-bit
  localparam logic [11:0] DIR_PAT = 12'h49A;

  task build_program(input int first_hw, input bit directed, input int p16);
    int h, n, k;
    bit is16;
    logic [31:0] v;
    for (int i = 0; i < HWN; i++) begin
      hw[i] = 16'h0000; e_instr[i] = 32'h0; e_comp[i] = 1'b0; e_start[i] = 1'b0;
    end
    h = first_hw;
    if (first_hw == 1) hw[0] = 16'h0001;                 // filler before the first instruction (boot at 0x2)
    for (n = 0; n < NIN; n++) begin
      is16 = directed ? DIR_PAT[n % 12] : pct(p16);
      start_pc[n] = h * 2;
      e_start[h]  = 1'b1;
      if (is16) begin
        // c.addi x<k>,<k>  ->  addi x<k>,x<k>,<k>   (k = 0 is c.nop)
        k = directed ? ((n % 7) + 1) : int'(rnd() % 32);
        hw[h]      = 16'((k << 7) | (k << 2) | 1);
        e_instr[h] = 32'((k << 20) | (k << 15) | (k << 7) | 32'h13);
        e_comp[h]  = 1'b1;
        h = h + 1;
      end else begin
        // directed: addi x5,x0,<n+1> ; random: any word whose low two bits are 11
        v = directed ? 32'(((n + 1) << 20) | 32'h293) : (rnd() | 32'h3);
        hw[h]      = v[15:0];
        hw[h + 1]  = v[31:16];
        e_instr[h] = v;
        e_comp[h]  = 1'b0;
        h = h + 2;
      end
    end
    end_limit_pc = start_pc[NIN - 20];
  endtask

  function logic [31:0] mem_word(input logic [31:0] addr);
    int w;
    w = int'(addr >> 2);
    if (2 * w + 1 < HWN) return {hw[2 * w + 1], hw[2 * w]};
    else                 return 32'h0;
  endfunction

  // ---------------------------------------------------------- test configuration
  int  cfg_gnt_pct   = 100;   // probability that a request is granted in a cycle (100 = never waits)
  int  cfg_lat_max   = 1;     // response latency 1..lat_max cycles after the grant
  int  cfg_rdy_pct   = 100;   // probability that decode accepts an instruction in a cycle
  int  cfg_redir_pct = 0;     // probability of a redirect in a cycle
  int  cfg_min_gap   = 3;     // minimum cycles between two redirects
  bit  cfg_trace     = 1'b0;

  // -------------------------------------------------- memory model + decode-side driver
  logic gnt_rnd_q = 1'b1;
  assign instr_gnt_i = instr_req_o & gnt_rnd_q;

  int unsigned q_addr [8];
  int          q_due  [8];
  int          q_wr, q_rd, q_cnt, last_due;
  int          cyc, tcyc, lat_d;

  // ------------------------------------------------------------------ scoreboard state
  int unsigned exp_pc;
  int          delivered, errors, hold_viol, reset_viol, n_redirect, gap;
  int          cov_straddle, cov_comp, cov_redir_pend, cov_stale, cov_full, cov_wait;
  bit          prev_req, prev_gnt;
  logic [31:0] prev_addr;
  int          tr_lines;

  always @(posedge clk) begin
    cyc  = cyc + 1;
    tcyc = tcyc + 1;

    // ---------------- OBI protocol checks on the instruction port
    if (!rst_ni) begin
      if (instr_req_o === 1'b1) begin reset_viol = reset_viol + 1; end
      prev_req = 1'b0;
    end else begin
      if (prev_req && !prev_gnt) begin
        if (!(instr_req_o === 1'b1 && instr_addr_o === prev_addr)) begin
          hold_viol = hold_viol + 1;
          $display("  ** OBI hold violation at cycle %0d: request/address changed before gnt", cyc);
        end
      end
      prev_req  = (instr_req_o === 1'b1);
      prev_gnt  = (instr_gnt_i === 1'b1);
      prev_addr = instr_addr_o;
    end

    // ---------------- memory model: accept a granted request
    if (!rst_ni) begin
      q_wr = 0; q_rd = 0; q_cnt = 0; last_due = 0;
    end else if (instr_req_o && instr_gnt_i) begin
      q_addr[q_wr] = instr_addr_o;
      lat_d        = cyc + 1 + int'(rnd() % cfg_lat_max);      // response visible in cycle lat_d
      q_due[q_wr]  = (lat_d > last_due + 1) ? lat_d : (last_due + 1);   // keep order, one response per cycle
      last_due     = q_due[q_wr];
      q_wr = (q_wr + 1) % 8; q_cnt = q_cnt + 1;
    end

    // ---------------- scoreboard: an instruction handed to decode in this cycle
    if (rst_ni && instr_valid_o && instr_ready_i) begin
      if (cfg_trace && tr_lines < 40)
        $display("  cyc %3d  DELIVER pc=0x%08h instr=0x%08h %s", cyc, pc_o, instr_o, is_compressed_o ? "(16-bit, expanded)" : "(32-bit)");
      if (pc_o !== exp_pc || !e_start[exp_pc >> 1] ||
          instr_o !== e_instr[exp_pc >> 1] || is_compressed_o !== e_comp[exp_pc >> 1]) begin
        errors = errors + 1;
        if (errors <= 5)
          $display("  ** MISMATCH cycle %0d: got pc=0x%08h instr=0x%08h comp=%0b, expected pc=0x%08h instr=0x%08h comp=%0b",
                   cyc, pc_o, instr_o, is_compressed_o, exp_pc, e_instr[exp_pc >> 1], e_comp[exp_pc >> 1]);
      end
      if (!is_compressed_o && pc_o[1]) cov_straddle = cov_straddle + 1;
      if (is_compressed_o) cov_comp = cov_comp + 1;
      delivered = delivered + 1;
      exp_pc    = exp_pc + (e_comp[exp_pc >> 1] ? 2 : 4);
    end
    // a redirect restarts the stream at the target (same cycle as the last delivery, if any)
    if (rst_ni && redirect_i) begin
      exp_pc = redirect_pc_i;
      n_redirect = n_redirect + 1;
      if (dut.pend_q) cov_redir_pend = cov_redir_pend + 1;
    end
    if (rst_ni && dut.resp_drop) cov_stale = cov_stale + 1;
    if (rst_ni && dut.count_q == 4) cov_full = cov_full + 1;
    if (rst_ni && instr_req_o && !instr_gnt_i) cov_wait = cov_wait + 1;

    // ---------------- cycle trace (first directed test)
    if (cfg_trace && rst_ni && tr_lines < 40) begin
      $display("  cyc %3d  req=%0b addr=0x%08h gnt=%0b | rvalid=%0b rdata=0x%08h | fifo=%0d inflight=%0d | valid=%0b",
               cyc, instr_req_o, instr_addr_o, instr_gnt_i, instr_rvalid_i, instr_rdata_i,
               dut.count_q, dut.inflight_q, instr_valid_o);
      tr_lines = tr_lines + 1;
    end

    // ---------------- drive the inputs for the NEXT cycle
    gnt_rnd_q <= pct(cfg_gnt_pct);
    instr_ready_i <= pct(cfg_rdy_pct);

    instr_rvalid_i <= 1'b0;
    instr_rdata_i  <= 32'hx;
    if (rst_ni && q_cnt > 0 && q_due[q_rd] <= cyc + 1) begin
      instr_rvalid_i <= 1'b1;
      instr_rdata_i  <= mem_word(q_addr[q_rd]);
      q_rd = (q_rd + 1) % 8; q_cnt = q_cnt - 1;
    end

    redirect_i <= 1'b0;
    if (gap > 0) gap = gap - 1;
    if (rst_ni && (redirect_i === 1'b0) && gap == 0 &&
        (exp_pc >= end_limit_pc || pct(cfg_redir_pct))) begin
      redirect_i    <= 1'b1;
      redirect_pc_i <= start_pc[rnd() % (NIN - 30)];
      gap = cfg_min_gap;
    end
  end

  // ------------------------------------------------------------------------ test runner
  int total_fail = 0, total_tests = 0;

  task run_test(input string name, input int boot, input int gnt_pct, input int lat_max, input int rdy_pct,
                input int redir_pct, input int n_deliver, input bit directed, input int p16, input bit trace);
    // reset first, then rebuild the program while the DUT is held in reset
    rst_ni = 1'b0;
    repeat (3) @(posedge clk);
    build_program(boot >> 1, directed, p16);
    cfg_gnt_pct = gnt_pct; cfg_lat_max = lat_max; cfg_rdy_pct = rdy_pct; cfg_redir_pct = redir_pct;
    cfg_trace = trace;
    boot_addr = boot;
    exp_pc = boot;
    delivered = 0; errors = 0; hold_viol = 0; reset_viol = 0; n_redirect = 0; gap = 0;
    cov_straddle = 0; cov_comp = 0; cov_redir_pend = 0; cov_stale = 0; cov_full = 0; cov_wait = 0;
    tcyc = 0; tr_lines = 0;
    redirect_i = 1'b0;
    @(negedge clk);
    rst_ni = 1'b1;
    while (delivered < n_deliver && tcyc < 200000) @(posedge clk);
    @(negedge clk);
    total_tests = total_tests + 1;
    if (errors == 0 && hold_viol == 0 && reset_viol == 0 && delivered >= n_deliver) begin
      $display("[PASS] %-44s instr=%0d cycles=%0d (%0.2f instr/cycle)", name, delivered, tcyc, real'(delivered) / real'(tcyc));
    end else begin
      total_fail = total_fail + 1;
      $display("[FAIL] %-44s instr=%0d/%0d cycles=%0d mismatches=%0d hold_violations=%0d req_in_reset=%0d",
               name, delivered, n_deliver, tcyc, errors, hold_viol, reset_viol);
    end
    $display("       covered: 16-bit=%0d straddling-32-bit=%0d redirects=%0d (while request pending=%0d) stale-words-dropped=%0d fifo-full-cycles=%0d wait-cycles=%0d",
             cov_comp, cov_straddle, n_redirect, cov_redir_pend, cov_stale, cov_full, cov_wait);
  endtask

  int tr;
  initial begin
    cyc = 0; tcyc = 0;
    instr_ready_i = 1'b1; instr_rvalid_i = 1'b0; instr_rdata_i = 32'h0;
    redirect_i = 1'b0; redirect_pc_i = 32'h0; boot_addr = 32'h0;
    prev_req = 1'b0; prev_gnt = 1'b0; prev_addr = 32'h0;
    q_wr = 0; q_rd = 0; q_cnt = 0; last_due = 0;
    tr = 0;
    void'($value$plusargs("trace=%d", tr));
    $display("=== rv_fetch block-level testbench ===");

    //        name                                              boot gnt lat rdy redir  n   dir p16 trace
    run_test("1 directed, ideal memory, boot 0x0",                0, 100, 1, 100,  0,   24, 1, 0, tr != 0);
    run_test("2 directed, ideal memory, boot 0x2 (upper half)",   2, 100, 1, 100,  0,   24, 1, 0, 1'b0);
    run_test("3 directed, wait states + decode back-pressure",    0,  50, 3,  60,  0,  120, 1, 0, 1'b0);
    run_test("4 random 16/32-bit mix, ideal memory",              0, 100, 1, 100,  0, 2000, 0, 50, 1'b0);
    run_test("5 random mix, wait states + back-pressure",         0,  40, 4,  50,  0, 2000, 0, 50, 1'b0);
    run_test("6 random mix, redirects, ideal memory",             0, 100, 1, 100, 10, 3000, 0, 50, 1'b0);
    run_test("7 random mix, redirects + wait states",             0,  50, 3,  70, 15, 3000, 0, 50, 1'b0);
    run_test("8 stress: slow memory, redirects, boot 0x2",        2,  30, 4,  30, 20, 3000, 0, 50, 1'b0);
    run_test("9 all 16-bit instructions, wait states",            0,  60, 3,  70,  5, 2000, 0, 100, 1'b0);
    run_test("10 all 32-bit instructions, wait states",           2,  60, 3,  70,  5, 2000, 0, 0, 1'b0);

    $display("=== %0d tests, %0d failed ===", total_tests, total_fail);
    if (total_fail == 0) $display("TB: PASS (rv_fetch block level)");
    else                 $display("TB: FAIL (rv_fetch block level)");
    $finish;
  end
endmodule
