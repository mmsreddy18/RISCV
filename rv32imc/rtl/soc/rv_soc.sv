// -----------------------------------------------------------------------------
// rv_soc.sv : rv_core + OBI interconnect + memories  (the smallest verifiable system)
//
//   core instr port ─┐                     ┌─ [0] ITCM 0x0000_0000..0x0001_FFFF  (RWX: fetch, and data port for tables/tests)
//                    ├─ pulp obi_xbar ─────┼─ [4] DTCM 0x0002_0000..0x0003_FFFF  (RW-, not executable)   <- separate SRAM
//   core data  port ─┘   (2 managers,      ├─ [1] ROM  0x0004_0000..0x0004_0FFF  (R-X, write -> err)
//                         5 subordinates)  ├─ [2] MMIO 0x1000_0000..0x1000_0FFF  (RW-, not executable, rv_obi_mmio)
//                                          └─ [3] ERR  everything else (obi_err_sbr: err=1)
//
//   Harvard layout: code runs from ITCM and data (variables, stack) lives in DTCM, two independent SRAMs, so an
//   instruction fetch and a data access in the same cycle never compete for one SRAM port.
//   SPLIT_MEM=0 gives the previous single 256 KiB SRAM at 0x0..0x3_FFFF (DTCM then sits unused at 0x7000_0000).
//   Execute permission is enforced by the crossbar connectivity matrix: an instruction fetch that
//   decodes to MMIO or DTCM is answered by the built-in err subordinate (-> instruction access fault).
//   Reset vector: boot_addr_i (default ROM base 0x0004_0000).
//   obi_xbar / obi_sram_shim / obi_err_sbr are the unmodified pulp-platform/obi sources.
// -----------------------------------------------------------------------------
`include "obi/typedef.svh"

module rv_soc
  import rv_pkg::*;
#(
  parameter bit          SPLIT_MEM     = 1'b1,            // 1: separate instruction / data memory, 0: one shared SRAM
  parameter int unsigned ITCM_WORDS    = 32768,           // 128 KiB
  parameter int unsigned DTCM_WORDS    = 32768,           // 128 KiB
  parameter int unsigned ROM_WORDS     = 1024,            // 4 KiB
  parameter bit          SRAM_STALL    = 1'b0,            // pseudo-random SRAM grant wait states (both memories)
  parameter int unsigned SRAM_CUTS     = 0,               // extra register slices (obi_cut) in front of each SRAM
  parameter bit          FAST_REDIRECT = 1'b0,
  parameter bit          BP_ENABLE     = 1'b1,
  parameter bit          ZICSR         = 1'b1,
  parameter bit          OBI_STRICT_REQ = 1'b1
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [31:0] boot_addr_i,
  // test-bench visibility (outputs of the MMIO block / core status)
  output logic        tohost_valid_o,
  output logic [31:0] tohost_o,
  output logic        putchar_valid_o,
  output logic [7:0]  putchar_o,
  output logic        roi_start_o,
  output logic        roi_stop_o,
  output logic        retire_o,
  output logic        trap_o
);
  localparam obi_pkg::obi_cfg_t Cfg = '{
    UseRReady: 1'b0, CombGnt: 1'b0, AddrWidth: 32, DataWidth: 32, IdWidth: 1,
    Integrity: 1'b0, BeFull: 1'b0, OptionalCfg: obi_pkg::ObiMinimalOptionalConfig };
  localparam int unsigned NSBR = 2;     // pulp naming: "subordinate ports" face the managers
  localparam int unsigned NMGR = 5;     // "manager ports" face the subordinates

  `OBI_TYPEDEF_MINIMAL_A_OPTIONAL(a_opt_t)
  `OBI_TYPEDEF_MINIMAL_R_OPTIONAL(r_opt_t)
  `OBI_TYPEDEF_A_CHAN_T(a_chan_t, 32, 32, 1, a_opt_t)
  `OBI_TYPEDEF_R_CHAN_T(r_chan_t, 32, 1, r_opt_t)
  `OBI_TYPEDEF_DEFAULT_REQ_T(req_t, a_chan_t)
  `OBI_TYPEDEF_RSP_T(rsp_t, r_chan_t)

  typedef struct packed { int unsigned idx; logic [31:0] start_addr; logic [31:0] end_addr; } rule_t;

  // ------------------------------------------------------------------ core
  logic        instr_req, instr_gnt, instr_rvalid, instr_err, data_req, data_gnt, data_we, data_rvalid, data_err;
  logic [31:0] instr_addr, instr_rdata, data_addr, data_wdata, data_rdata;
  logic [3:0]  data_be;
  logic        irq_sw, irq_tm, irq_ex, ecall, ebreak, illegal, mret;

  rv_core #(.FAST_REDIRECT(FAST_REDIRECT), .BP_ENABLE(BP_ENABLE), .ZICSR(ZICSR), .OBI_STRICT_REQ(OBI_STRICT_REQ)) u_core (
    .clk_i, .rst_ni, .boot_addr_i, .hart_id_i(32'h0),
    .irq_software_i(irq_sw), .irq_timer_i(irq_tm), .irq_external_i(irq_ex),
    .instr_req_o(instr_req), .instr_gnt_i(instr_gnt), .instr_addr_o(instr_addr),
    .instr_rvalid_i(instr_rvalid), .instr_rdata_i(instr_rdata), .instr_err_i(instr_err),
    .data_req_o(data_req), .data_gnt_i(data_gnt), .data_addr_o(data_addr), .data_we_o(data_we),
    .data_be_o(data_be), .data_wdata_o(data_wdata), .data_rvalid_i(data_rvalid), .data_rdata_i(data_rdata),
    .data_err_i(data_err),
    .retire_o, .ecall_o(ecall), .ebreak_o(ebreak), .illegal_o(illegal), .trap_o, .mret_o(mret)
  );

  // ------------------------------------------------------- flat ports <-> OBI structs
  req_t [NSBR-1:0] mgr_req;     // from the two managers (xbar "sbr_ports")
  rsp_t [NSBR-1:0] mgr_rsp;
  always_comb begin
    mgr_req[0]        = '0;
    mgr_req[0].req    = instr_req;
    mgr_req[0].a.addr = instr_addr;
    mgr_req[0].a.be   = 4'b1111;                 // instruction fetch: full word, read
    mgr_req[1]        = '0;
    mgr_req[1].req    = data_req;
    mgr_req[1].a.addr = data_addr;
    mgr_req[1].a.we   = data_we;
    mgr_req[1].a.be   = data_be;
    mgr_req[1].a.wdata = data_wdata;
  end
  assign instr_gnt    = mgr_rsp[0].gnt;
  assign instr_rvalid = mgr_rsp[0].rvalid;
  assign instr_rdata  = mgr_rsp[0].r.rdata;
  assign instr_err    = mgr_rsp[0].r.err;
  assign data_gnt     = mgr_rsp[1].gnt;
  assign data_rvalid  = mgr_rsp[1].rvalid;
  assign data_rdata   = mgr_rsp[1].r.rdata;
  assign data_err     = mgr_rsp[1].r.err;

  // ------------------------------------------------------------------ crossbar
  req_t [NMGR-1:0] sub_req;
  rsp_t [NMGR-1:0] sub_rsp;
  localparam int unsigned IT_WORDS = SPLIT_MEM ? ITCM_WORDS : (ITCM_WORDS + DTCM_WORDS);
  localparam logic [31:0] DT_BASE  = SPLIT_MEM ? 32'(ITCM_WORDS * 4) : 32'h7000_0000;
  rule_t [3:0] addr_map;
  assign addr_map[0] = '{idx: 32'd0, start_addr: 32'h0000_0000, end_addr: 32'(IT_WORDS * 4)};       // ITCM (or the shared SRAM)
  assign addr_map[1] = '{idx: 32'd1, start_addr: 32'h0004_0000, end_addr: 32'h0004_1000};           // ROM
  assign addr_map[2] = '{idx: 32'd2, start_addr: 32'h1000_0000, end_addr: 32'h1000_1000};           // MMIO
  assign addr_map[3] = '{idx: 32'd4, start_addr: DT_BASE,       end_addr: DT_BASE + 32'(DTCM_WORDS * 4)};  // DTCM
  // connectivity[manager][subordinate], bits {DTCM, ERR, MMIO, ROM, ITCM}: the instruction port may reach ITCM, ROM and ERR only
  localparam bit [NSBR-1:0][NMGR-1:0] CONN = {5'b11111, 5'b01011};

  obi_xbar #(
    .SbrPortObiCfg(Cfg), .sbr_port_obi_req_t(req_t), .sbr_port_a_chan_t(a_chan_t),
    .sbr_port_obi_rsp_t(rsp_t), .sbr_port_r_chan_t(r_chan_t),
    .NumSbrPorts(NSBR), .NumMgrPorts(NMGR), .NumMaxTrans(4), .NumAddrRules(4),
    .addr_map_rule_t(rule_t), .UseIdForRouting(1'b0), .Connectivity(CONN)
  ) u_xbar (
    .clk_i, .rst_ni, .testmode_i(1'b0),
    .sbr_ports_req_i(mgr_req), .sbr_ports_rsp_o(mgr_rsp),
    .mgr_ports_req_o(sub_req), .mgr_ports_rsp_i(sub_rsp),
    .addr_map_i(addr_map),
    .en_default_idx_i({NSBR{1'b1}}), .default_idx_i({NSBR{3'd3}})      // unmapped -> ERR subordinate
  );

  // ------------------------------------------------------- [0] ITCM and [4] DTCM (two independent SRAMs)
  rv_obi_mem #(.ObiCfg(Cfg), .obi_a_chan_t(a_chan_t), .obi_r_chan_t(r_chan_t), .obi_req_t(req_t), .obi_rsp_t(rsp_t),
               .WORDS(IT_WORDS), .BASE_WORD(0), .IMG_WORDS(65536), .STALL(SRAM_STALL), .CUTS(SRAM_CUTS)) u_itcm (
    .clk_i, .rst_ni, .req_i(sub_req[0]), .rsp_o(sub_rsp[0]));
  rv_obi_mem #(.ObiCfg(Cfg), .obi_a_chan_t(a_chan_t), .obi_r_chan_t(r_chan_t), .obi_req_t(req_t), .obi_rsp_t(rsp_t),
               .WORDS(DTCM_WORDS), .BASE_WORD(SPLIT_MEM ? ITCM_WORDS : 65536), .IMG_WORDS(65536), .STALL(SRAM_STALL), .CUTS(SRAM_CUTS)) u_dtcm (
    .clk_i, .rst_ni, .req_i(sub_req[4]), .rsp_o(sub_rsp[4]));

  // ----------------------------------------------------------------- [1] ROM
  logic rom_gnt, rom_rvalid, rom_err; logic [31:0] rom_rdata;
  rv_obi_rom #(.WORDS(ROM_WORDS)) u_rom (
    .clk_i, .rst_ni, .req_i(sub_req[1].req), .we_i(sub_req[1].a.we), .addr_i(sub_req[1].a.addr),
    .gnt_o(rom_gnt), .rvalid_o(rom_rvalid), .rdata_o(rom_rdata), .err_o(rom_err));
  always_comb begin
    sub_rsp[1]         = '0;
    sub_rsp[1].gnt     = rom_gnt;
    sub_rsp[1].rvalid  = rom_rvalid;
    sub_rsp[1].r.rdata = rom_rdata;
    sub_rsp[1].r.err   = rom_err;
  end

  // ---------------------------------------------------------------- [2] MMIO
  logic mm_gnt, mm_rvalid, mm_err; logic [31:0] mm_rdata;
  rv_obi_mmio u_mmio (
    .clk_i, .rst_ni, .req_i(sub_req[2].req), .we_i(sub_req[2].a.we), .addr_i(sub_req[2].a.addr),
    .wdata_i(sub_req[2].a.wdata), .gnt_o(mm_gnt), .rvalid_o(mm_rvalid), .rdata_o(mm_rdata), .err_o(mm_err),
    .irq_software_o(irq_sw), .irq_timer_o(irq_tm), .irq_external_o(irq_ex),
    .tohost_valid_o, .tohost_o, .putchar_valid_o, .putchar_o, .roi_start_o, .roi_stop_o);
  always_comb begin
    sub_rsp[2]         = '0;
    sub_rsp[2].gnt     = mm_gnt;
    sub_rsp[2].rvalid  = mm_rvalid;
    sub_rsp[2].r.rdata = mm_rdata;
    sub_rsp[2].r.err   = mm_err;
  end

  // ------------------------------------------------------------------ [3] ERR
  obi_err_sbr #(.ObiCfg(Cfg), .obi_req_t(req_t), .obi_rsp_t(rsp_t), .NumMaxTrans(4), .RspData(32'hBADCAB1E)) u_err (
    .clk_i, .rst_ni, .testmode_i(1'b0), .obi_req_i(sub_req[3]), .obi_rsp_o(sub_rsp[3]));


`ifdef OBI_ASSERT
  // ---------------------------------------------------------------------------------------
  // Third-party protocol assertions (pulp-platform/obi obi_asserter, see verif/third_party) on
  // every link: the two core ports (core = manager) and the four crossbar outputs (memories).
  // All managers here have rready tied high (no rready signal in this configuration).
  // ---------------------------------------------------------------------------------------
  `OBI_TYPEDEF_REQ_T(areq_t, a_chan_t)
  areq_t [NSBR-1:0] a_mgr;
  areq_t [NMGR-1:0] a_sub;
  always_comb begin
    for (int i = 0; i < NSBR; i++) begin a_mgr[i].a = mgr_req[i].a; a_mgr[i].req = mgr_req[i].req; a_mgr[i].rready = 1'b1; end
    for (int i = 0; i < NMGR; i++) begin a_sub[i].a = sub_req[i].a; a_sub[i].req = sub_req[i].req; a_sub[i].rready = 1'b1; end
  end
  for (genvar i = 0; i < NSBR; i++) begin : g_asrt_mgr
    obi_asserter #(.obi_req_t(areq_t), .obi_rsp_t(rsp_t)) u_a (.clk_i, .rst_ni, .obi_req_i(a_mgr[i]), .obi_rsp_i(mgr_rsp[i]));
  end
  for (genvar i = 0; i < NMGR; i++) begin : g_asrt_sub
    obi_asserter #(.obi_req_t(areq_t), .obi_rsp_t(rsp_t)) u_a (.clk_i, .rst_ni, .obi_req_i(a_sub[i]), .obi_rsp_i(sub_rsp[i]));
  end
`endif

  // unused status
  logic unused;
  assign unused = &{1'b0, ecall, ebreak, illegal, mret};
endmodule
