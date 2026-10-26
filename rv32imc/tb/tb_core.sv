// -----------------------------------------------------------------------------
// tb_core.sv : self-contained testbench for rv_core
//   * One unified memory behind OBI-style instruction and data ports.
//   * +stall=1 enables random gnt de-assertion and random response latency on
//     both ports (stress for the hazard / stall logic).
//   * Magic addresses (data port, 0x1000_0000 range):
//        0x1000_0000  store = test result (1 = PASS), ends the simulation
//        0x1000_0004  store = putchar
//        0x1000_0010  store = software-interrupt line level (bit 0)
//        0x1000_0014  store = external-interrupt line level (bit 0)
//        0x1000_0018  store N = raise timer interrupt after N cycles (0 = clear it)
//   Error injection: any access (either port) to 0x2000_0000..0x2FFF_FFFF and to the top 16 KiB of
//   RAM (0x0003_C000..0x0003_FFFF) returns an OBI err only with +errram=1
//   response (reads return 0xBAD0_xxxx data, writes are ignored).
//   Plusargs: +hex=<file> +stall=<0|1> +seed=<n> +maxcyc=<n> +dump=<file>
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_core;

  parameter bit FAST_REDIRECT = 1'b0;
  parameter int FETCH_DEPTH   = 4;
  parameter bit BP_ENABLE     = 1'b1;
  parameter bit ZICSR         = 1'b1;
  parameter bit GSHARE        = 1'b0;
  parameter bit OBI_FATAL     = 1'b0;   // 1: stop at the first OBI protocol violation
  parameter int BTB_N = 16, BTB_W = 4, BHT_N = 64, BHT_W = 6, RAS_N = 8, RAS_W = 3;

  localparam int MEM_WORDS = 65536;       // 256 KiB
  localparam int DUMP_BASE = 32'h0000_4000;
  localparam int DUMP_WORDS = 256;

  // addresses that answer with an OBI err response (either port)
  bit err_ram = 1'b0;   // +errram=1 : top 16 KiB of RAM also answers with err (access_faults test only)
  function automatic bit is_err_addr(input logic [31:0] a);
    return (a[31:28] == 4'h2) || (err_ram && a >= 32'h0003_C000 && a < 32'h0004_0000);
  endfunction

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  // DUT ports
  logic        instr_req, instr_gnt, instr_rvalid, instr_err = 1'b0, data_err = 1'b0;
  logic [31:0] instr_addr, instr_rdata;
  logic        data_req, data_gnt, data_we, data_rvalid;
  logic [31:0] data_addr, data_wdata, data_rdata;
  logic [3:0]  data_be;
  logic        retire, ecall, ebreak, illegal, trap, mret;
  logic        irq_sw = 1'b0, irq_tm = 1'b0, irq_ex = 1'b0;

  rv_core #(.FETCH_DEPTH(FETCH_DEPTH), .FAST_REDIRECT(FAST_REDIRECT), .BP_ENABLE(BP_ENABLE), .ZICSR(ZICSR), .GSHARE(GSHARE),
          .BTB_N(BTB_N), .BTB_W(BTB_W), .BHT_N(BHT_N), .BHT_W(BHT_W), .RAS_N(RAS_N), .RAS_W(RAS_W)) dut (
    .clk_i(clk), .rst_ni(rst_n), .boot_addr_i(32'h0000_0000), .hart_id_i(32'h0),
    .irq_software_i(irq_sw), .irq_timer_i(irq_tm), .irq_external_i(irq_ex),
    .instr_req_o(instr_req), .instr_gnt_i(instr_gnt), .instr_addr_o(instr_addr),
    .instr_rvalid_i(instr_rvalid), .instr_rdata_i(instr_rdata), .instr_err_i(instr_err),
    .data_req_o(data_req), .data_gnt_i(data_gnt), .data_addr_o(data_addr),
    .data_we_o(data_we), .data_be_o(data_be), .data_wdata_o(data_wdata),
    .data_rvalid_i(data_rvalid), .data_rdata_i(data_rdata), .data_err_i(data_err),
    .retire_o(retire), .ecall_o(ecall), .ebreak_o(ebreak), .illegal_o(illegal),
    .trap_o(trap), .mret_o(mret)
  );


  // OBI 1.6.0 protocol checkers on both ports (core = manager, testbench memory = subordinate)
  obi_checker #(.NAME("instr"), .DATA(1'b0), .FATAL(OBI_FATAL)) u_obi_i (
    .clk_i(clk), .rst_ni(rst_n), .req_i(instr_req), .gnt_i(instr_gnt), .addr_i(instr_addr),
    .we_i(1'b0), .be_i(4'b1111), .wdata_i(32'h0), .rvalid_i(instr_rvalid));
  obi_checker #(.NAME("data"), .DATA(1'b1), .FATAL(OBI_FATAL)) u_obi_d (
    .clk_i(clk), .rst_ni(rst_n), .req_i(data_req), .gnt_i(data_gnt), .addr_i(data_addr),
    .we_i(data_we), .be_i(data_be), .wdata_i(data_wdata), .rvalid_i(data_rvalid));

  // ------------------------------------------------------------------ memory
  logic [31:0] mem [MEM_WORDS];

  // xorshift32 PRNG (portable, seedable)
  int unsigned rng_state;
  function automatic int unsigned rng();
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 17;
    rng_state ^= rng_state << 5;
    return rng_state;
  endfunction

  bit          stall_en;
  bit          trace_en;
  bit          trace_en_i;
  int unsigned cycle = 0;
  bit          ig_q, dg_q;   // random grant enables (registered)
  int unsigned tm_cnt = 0;   // timer-interrupt countdown (0 = idle)

  assign instr_gnt = instr_req & ig_q;
  assign data_gnt  = data_req  & dg_q;

  // response queues (in-order)
  logic [31:0] iq_data [$];
  int unsigned iq_rdy  [$];
  int unsigned i_last_rdy = 0;
  bit          iq_err  [$];
  bit          dq_err  [$];
  logic [31:0] dq_data [$];
  int unsigned dq_rdy  [$];
  int unsigned d_last_rdy = 0;

  int unsigned n_retired = 0, n_illegal = 0;
  bit          done = 1'b0;
  logic [31:0] tohost = 32'h0;
  int unsigned done_cnt = 0;

  // Deterministic memory knobs (used when +stall=0):
  //   +ilat/+dlat : extra response latency in cycles (0 = response one cycle after grant)
  //   +igw/+dgw   : grant wait states; grant is offered 1 cycle in (N+1)
  int unsigned ilat = 0, dlat = 0, igw = 0, dgw = 0;

  function automatic int unsigned extra_lat_i();
    return stall_en ? (rng() % 4) : ilat;
  endfunction
  function automatic int unsigned extra_lat_d();
    return stall_en ? (rng() % 4) : dlat;
  endfunction

  // ---------------------------------------------------------- perf counters
  // Every cycle from reset release to the final result store is charged to the
  // ID issue slot: either an instruction issues, or exactly one stall cause.
  localparam int NP = 22;
  localparam int P_CYC=0, P_ISSUE=1, P_FETCH=2, P_BRANCH=3, P_LOADUSE=4, P_EXMUL=5, P_EXDIV=6,
                 P_EXMEM=7, P_WBSTALL=8, P_LD=9, P_ST=10, P_BR=11, P_TAKEN=12, P_JAL=13,
                 P_JALR=14, P_MUL=15, P_MULH=16, P_DIV=17, P_RVC=18, P_IFETCH=19, P_IDROP=20,
                 P_DREQ=21;
  string pnames [NP] = '{"cycles","issued","fetch","branch","loaduse","exmul","exdiv","exmem",
                         "wbstall","loads","stores","branches","taken","jal","jalr","mul","mulh",
                         "div","rvc","ifetch","idrop","dreq"};
  bit perf_en = 1'b0;
  bit flush_pend = 1'b0;
  longint unsigned p [NP];
  longint unsigned snap_a [NP];
  longint unsigned snap_b [NP];
  bit roi_start_seen = 1'b0, roi_stop_seen = 1'b0;
  // stores to 0x1000_0008 / 0x1000_000C mark the start / end of a timed region
  task automatic print_perf(input string tag, input longint unsigned v [NP]);
    longint unsigned stalls;
    stalls = 0;
    for (int i = P_FETCH; i <= P_WBSTALL; i++) stalls += v[i];
    $write("%s", tag);
    for (int i = 0; i < NP; i++) $write(" %s=%0d", pnames[i], v[i]);
    $display(" check=%0d", (v[P_ISSUE] + stalls) == v[P_CYC]);
  endtask

  always @(posedge clk) begin
    if (!rst_n) begin
      instr_rvalid <= 1'b0;
      data_rvalid  <= 1'b0;
      ig_q         <= 1'b1;
      dg_q         <= 1'b1;
    end else begin
      cycle <= cycle + 1;
      if (tm_cnt != 0) begin
        tm_cnt <= tm_cnt - 1;
        if (tm_cnt == 1) irq_tm <= 1'b1;
      end
      ig_q  <= stall_en ? ((rng() % 4) != 0) : ((igw == 0) ? 1'b1 : (cycle % (igw + 1) == 0));
      dg_q  <= stall_en ? ((rng() % 4) != 0) : ((dgw == 0) ? 1'b1 : (cycle % (dgw + 1) == 0));

      // ---- performance accounting (samples DUT state before this edge)
      if (perf_en && !done) begin
        p[P_CYC]++;
        if (instr_req && instr_gnt)   p[P_IFETCH]++;
        if (dut.u_fetch.resp_drop)    p[P_IDROP]++;
        if (data_req && data_gnt)     p[P_DREQ]++;
        if (dut.id_issue) begin
          p[P_ISSUE]++;
          if (dut.id_comp_q)   p[P_RVC]++;
          if (dut.id_is_load)  p[P_LD]++;
          if (dut.id_is_store) p[P_ST]++;
          if (dut.id_is_branch) begin p[P_BR]++; if (dut.redirect) p[P_TAKEN]++; end
          if (dut.id_is_jal)   p[P_JAL]++;
          if (dut.id_is_jalr)  p[P_JALR]++;
          if (dut.id_is_mul)   begin if (dut.id_f3 == 3'b000) p[P_MUL]++; else p[P_MULH]++; end
          if (dut.id_is_div)   p[P_DIV]++;
        end else if (dut.wb_stall) begin
          p[P_WBSTALL]++;                                // WB waiting for data rvalid
        end else if (dut.ex_valid_q && !dut.ex_complete) begin
          if      (dut.ex_is_mem) p[P_EXMEM]++;          // EX waiting for data gnt
          else if (dut.ex_mul_q)  p[P_EXMUL]++;          // multi-cycle MULH*
          else                    p[P_EXDIV]++;          // iterative divider
        end else if (!dut.id_valid_q) begin
          if (flush_pend) p[P_BRANCH]++;                 // refilling after a taken branch/jump
          else            p[P_FETCH]++;                  // instruction supply starved
        end else begin
          p[P_LOADUSE]++;                                // load-use bubble
        end
        if (dut.redirect)         flush_pend = 1'b1;
        else if (dut.id_valid_q)  flush_pend = 1'b0;
      end

      if (retire)  n_retired <= n_retired + 1;
      if (illegal) n_illegal <= n_illegal + 1;

      // ---- instruction port
      if (instr_req && instr_gnt) begin
        int unsigned r;
        r = cycle + 1 + extra_lat_i();
        if (r <= i_last_rdy) r = i_last_rdy + 1;
        i_last_rdy = r;
        if (is_err_addr(instr_addr)) begin iq_data.push_back(32'hBAD0_0000 | instr_addr[15:0]); iq_err.push_back(1'b1); end
        else begin iq_data.push_back(mem[instr_addr[31:2] % MEM_WORDS]); iq_err.push_back(1'b0); end
        iq_rdy.push_back(r);
      end
      instr_rvalid <= 1'b0;
      instr_err    <= 1'b0;
      if (iq_data.size() != 0 && iq_rdy[0] <= cycle + 1) begin
        instr_rvalid <= 1'b1;
        instr_err    <= iq_err.pop_front();
        instr_rdata  <= iq_data.pop_front();
        void'(iq_rdy.pop_front());
      end

      // ---- data port
      if (data_req && data_gnt) begin
        int unsigned r;
        logic [31:0] w, m, rd;
        w  = mem[data_addr[31:2] % MEM_WORDS];
        rd = w;
        if (data_addr[31:28] == 4'h1) begin
          if (data_we && data_addr[4:0] == 5'h0) begin
            tohost = data_wdata;
            done   = 1'b1;
          end else if (data_we && data_addr[4:0] == 5'h4) begin
            $write("%c", data_wdata[7:0]);
          end else if (data_we && data_addr[4:0] == 5'h10) begin
            irq_sw <= data_wdata[0];                         // software interrupt level
          end else if (data_we && data_addr[4:0] == 5'h14) begin
            irq_ex <= data_wdata[0];                         // external interrupt level
          end else if (data_we && data_addr[4:0] == 5'h18) begin
            irq_tm <= 1'b0;                                  // timer: fires after N cycles, 0 clears
            tm_cnt <= data_wdata;
          end else if (data_we && data_addr[4:0] == 5'h8) begin
            for (int i = 0; i < NP; i++) snap_a[i] = p[i];
            roi_start_seen = 1'b1;
          end else if (data_we && data_addr[4:0] == 5'hC) begin
            for (int i = 0; i < NP; i++) snap_b[i] = p[i];
            roi_stop_seen = 1'b1;
          end
        end else if (is_err_addr(data_addr)) begin
          rd = 32'hBAD0_0000 | data_addr[15:0];                // error region: writes ignored
        end else if (data_we) begin
          m = {{8{data_be[3]}}, {8{data_be[2]}}, {8{data_be[1]}}, {8{data_be[0]}}};
          mem[data_addr[31:2] % MEM_WORDS] = (w & ~m) | (data_wdata & m);
        end
        r = cycle + 1 + extra_lat_d();
        if (r <= d_last_rdy) r = d_last_rdy + 1;
        d_last_rdy = r;
        dq_data.push_back(rd);
        dq_err.push_back(is_err_addr(data_addr));
        dq_rdy.push_back(r);
      end
      data_rvalid <= 1'b0;
      data_err    <= 1'b0;
      if (dq_data.size() != 0 && dq_rdy[0] <= cycle + 1) begin
        data_rvalid <= 1'b1;
        data_err    <= dq_err.pop_front();
        data_rdata  <= dq_data.pop_front();
        void'(dq_rdy.pop_front());
      end

      if (done) done_cnt <= done_cnt + 1;
    end
  end

  // ------------------------------------------------------------------ trace
  always @(posedge clk) begin
    if (rst_n && trace_en && trap)
      $display("[%0d] TRAP cause=%0d irq=%b pc=%08x", cycle, dut.trap_cause, dut.take_irq, dut.ex_trap ? dut.ex_pc_q : dut.id_pc_q);
    if (rst_n && trace_en && (dut.instret_inc != 0 || dut.wb_trap))
      $display("[%0d] instret inc=%0d wb_trap=%0d csr_ex=%b", cycle, dut.instret_inc, dut.wb_trap, dut.ex_csr_q);
    if (rst_n && trace_en && mret)
      $display("[%0d] MRET -> %08x", cycle, dut.mepc);
    if (rst_n && trace_en && data_req && data_gnt)
      $display("[%0d] D %s addr=%08x be=%b wdata=%08x", cycle, data_we ? "ST" : "LD", data_addr, data_be, data_wdata);
    if (rst_n && trace_en && trace_en_i && instr_req && instr_gnt)
      $display("[%0d] I addr=%08x", cycle, instr_addr);
  end

  // ------------------------------------------------------------ run control
  string hexfile, dumpfile;
  int unsigned maxcyc;
  int fd;

  initial begin
    int unsigned seed;
    stall_en = 0; seed = 1; maxcyc = 2_000_000; hexfile = "prog.hex"; dumpfile = "";
    trace_en = 0; trace_en_i = 0;
    void'($value$plusargs("trace=%d", trace_en));
    void'($value$plusargs("tracei=%d", trace_en_i));
    void'($value$plusargs("stall=%d", stall_en));
    void'($value$plusargs("perf=%d", perf_en));
    void'($value$plusargs("ilat=%d", ilat));
    void'($value$plusargs("dlat=%d", dlat));
    void'($value$plusargs("igw=%d", igw));
    void'($value$plusargs("dgw=%d", dgw));
    void'($value$plusargs("seed=%d", seed));
    void'($value$plusargs("maxcyc=%d", maxcyc));
    begin int e; if ($value$plusargs("errram=%d", e)) err_ram = (e != 0); end
    void'($value$plusargs("hex=%s", hexfile));
    void'($value$plusargs("dump=%s", dumpfile));
    rng_state = seed * 32'h9E3779B9 + 32'h1234567;
    if (rng_state == 0) rng_state = 1;

    for (int i = 0; i < MEM_WORDS; i++) mem[i] = 32'h0;
    for (int i = 0; i < NP; i++) begin p[i] = 0; snap_a[i] = 0; snap_b[i] = 0; end
    $readmemh(hexfile, mem);


    repeat (4) @(posedge clk);
    rst_n <= 1'b1;

    while (!(done && done_cnt > 12) && cycle < maxcyc) @(posedge clk);

    if (dumpfile != "") begin
      fd = $fopen(dumpfile, "w");
      for (int i = 1; i < 32; i++) $fdisplay(fd, "x%0d %08x", i, dut.u_rf.regs_q[i]);
      for (int i = 0; i < DUMP_WORDS; i++)
        $fdisplay(fd, "m%08x %08x", DUMP_BASE + 4*i, mem[DUMP_BASE/4 + i]);
      $fclose(fd);
    end

    if (perf_en) begin
      print_perf("PERF", p);
      if (roi_start_seen && roi_stop_seen) begin
        longint unsigned d [NP];
        for (int i = 0; i < NP; i++) d[i] = snap_b[i] - snap_a[i];
        print_perf("PERFROI", d);
      end
    end

    if (!done) begin
      $display("TB: TIMEOUT after %0d cycles (retired=%0d)", cycle, n_retired);
      $finish;
    end else if (tohost == 32'd1) begin
      $display("TB: PASS  cycles=%0d retired=%0d illegal=%0d", cycle, n_retired, n_illegal);
      $finish;
    end else begin
      $display("TB: FAIL  tohost=0x%08x (test #%0d) cycles=%0d", tohost, tohost >> 1, cycle);
      $finish;
    end
  end

endmodule
