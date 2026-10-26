// -----------------------------------------------------------------------------
// rv32imc_sys.sv : the core + separate instruction and data memory, connected through OBI.
//
//        instruction port ──► decoder ─┬─► IMEM port A  (fetch)                      0x0000_0000 + IMEM_BYTES
//                                      └─► error responder (anything that is not IMEM = fetch access fault)
//        data port ────────► decoder ─┬─► IMEM port B  (data access to the code memory, same BRAM)
//                                      ├─► DMEM         (separate block RAM)           0x0001_0000 + DMEM_BYTES
//                                      ├─► MMIO         (tohost, putchar, timer, irq)  0x1000_0000 + 0x1000
//                                      └─► error responder (unmapped address -> load/store access fault)
//
//   * No third-party code, no crossbar: each decoder is a few comparators.
//   * Every target has a fixed 1-cycle response, so at most one target answers per cycle and the
//     response is simply OR-ed together (each target's data is gated by its own rvalid).
//   * req from the core goes only to the selected target; gnt comes back from that target.
//     The core's request never depends on gnt (OBI_STRICT_REQ=1), so there is no combinational loop.
//   * Address map and sizes are parameters.  IMEM_INIT / DMEM_INIT: $readmemh images for synthesis
//     (the testbench loads images directly, see tb_sys.sv).
// -----------------------------------------------------------------------------
module rv32imc_sys #(
  parameter bit          BP_ENABLE      = 1'b1,
  parameter bit          ZICSR          = 1'b1,
  parameter bit          FAST_REDIRECT  = 1'b0,
  parameter bit          OBI_STRICT_REQ = 1'b1,
  // branch predictor sizes (used when BP_ENABLE=1): BTB entries (fully associative), BHT counters, return-stack entries
  parameter int unsigned BTB_N          = 16,
  parameter int unsigned BTB_W          = 4,        // log2(BTB_N)
  parameter int unsigned BHT_N          = 64,
  parameter int unsigned BHT_W          = 6,        // log2(BHT_N)
  parameter int unsigned RAS_N          = 8,
  parameter int unsigned RAS_W          = 3,        // log2(RAS_N)
  parameter bit          GSHARE         = 1'b0,
  parameter int unsigned IMEM_BYTES     = 32768,
  parameter int unsigned DMEM_BYTES     = 32768,
  parameter logic [31:0] IMEM_BASE      = 32'h0000_0000,
  parameter logic [31:0] DMEM_BASE      = 32'h0001_0000,
  parameter logic [31:0] MMIO_BASE      = 32'h1000_0000,
  parameter string       IMEM_INIT      = "",
  parameter string       DMEM_INIT      = "",
  parameter bit          MEM_STALL      = 1'b0      // random wait states on every memory port (testing)
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [31:0] boot_addr_i,
  // visibility for the testbench / board (outputs of the MMIO block and core status)
  output logic        tohost_valid_o,
  output logic [31:0] tohost_o,
  output logic        putchar_valid_o,
  output logic [7:0]  putchar_o,
  output logic        roi_start_o,
  output logic        roi_stop_o,
  output logic        retire_o,
  output logic        trap_o
);
  localparam int unsigned IW = IMEM_BYTES / 4;
  localparam int unsigned DW = DMEM_BYTES / 4;

  // ------------------------------------------------------------------ core
  logic        instr_req, instr_gnt, instr_rvalid, instr_err;
  logic [31:0] instr_addr, instr_rdata;
  logic        data_req, data_gnt, data_we, data_rvalid, data_err;
  logic [31:0] data_addr, data_wdata, data_rdata;
  logic [3:0]  data_be;
  logic        irq_sw, irq_tm, irq_ex, ecall, ebreak, illegal, mret;

  rv_core #(.FAST_REDIRECT(FAST_REDIRECT), .BP_ENABLE(BP_ENABLE), .ZICSR(ZICSR), .OBI_STRICT_REQ(OBI_STRICT_REQ),
           .BTB_N(BTB_N), .BTB_W(BTB_W), .BHT_N(BHT_N), .BHT_W(BHT_W), .RAS_N(RAS_N), .RAS_W(RAS_W), .GSHARE(GSHARE)) u_core (
    .clk_i, .rst_ni, .boot_addr_i, .hart_id_i(32'h0),
    .irq_software_i(irq_sw), .irq_timer_i(irq_tm), .irq_external_i(irq_ex),
    .instr_req_o(instr_req), .instr_gnt_i(instr_gnt), .instr_addr_o(instr_addr),
    .instr_rvalid_i(instr_rvalid), .instr_rdata_i(instr_rdata), .instr_err_i(instr_err),
    .data_req_o(data_req), .data_gnt_i(data_gnt), .data_addr_o(data_addr), .data_we_o(data_we),
    .data_be_o(data_be), .data_wdata_o(data_wdata), .data_rvalid_i(data_rvalid), .data_rdata_i(data_rdata),
    .data_err_i(data_err),
    .retire_o, .ecall_o(ecall), .ebreak_o(ebreak), .illegal_o(illegal), .trap_o, .mret_o(mret)
  );

  function automatic logic in_range(input logic [31:0] a, input logic [31:0] base, input logic [31:0] size);
    return (a - base) < size;
  endfunction

  // ---------------------------------------------------- instruction side decoder
  logic        i_sel_imem, i_sel_err;
  assign i_sel_imem = in_range(instr_addr, IMEM_BASE, 32'(IMEM_BYTES));
  assign i_sel_err  = ~i_sel_imem;

  // ---------------------------------------------------------- data side decoder
  logic        d_sel_imem, d_sel_dmem, d_sel_mmio, d_sel_err;
  assign d_sel_imem = in_range(data_addr, IMEM_BASE, 32'(IMEM_BYTES));
  assign d_sel_dmem = in_range(data_addr, DMEM_BASE, 32'(DMEM_BYTES));
  assign d_sel_mmio = in_range(data_addr, MMIO_BASE, 32'h0000_1000);
  assign d_sel_err  = ~(d_sel_imem | d_sel_dmem | d_sel_mmio);

  // ------------------------------------------------------------------ IMEM
  logic        im_i_gnt, im_i_rvalid, im_i_err, im_d_gnt, im_d_rvalid, im_d_err;
  logic [31:0] im_i_rdata, im_d_rdata;
  rv_obi_imem #(.WORDS(IW), .INIT_FILE(IMEM_INIT), .STALL(MEM_STALL)) u_imem (
    .clk_i, .rst_ni,
    .i_req_i(instr_req & i_sel_imem), .i_addr_i(instr_addr - IMEM_BASE),
    .i_gnt_o(im_i_gnt), .i_rvalid_o(im_i_rvalid), .i_rdata_o(im_i_rdata), .i_err_o(im_i_err),
    .d_req_i(data_req & d_sel_imem), .d_we_i(data_we), .d_addr_i(data_addr - IMEM_BASE), .d_be_i(data_be),
    .d_wdata_i(data_wdata),
    .d_gnt_o(im_d_gnt), .d_rvalid_o(im_d_rvalid), .d_rdata_o(im_d_rdata), .d_err_o(im_d_err));

  // ------------------------------------------------------------------ DMEM
  logic        dm_gnt, dm_rvalid, dm_err;
  logic [31:0] dm_rdata;
  rv_obi_dmem #(.WORDS(DW), .INIT_FILE(DMEM_INIT), .STALL(MEM_STALL)) u_dmem (
    .clk_i, .rst_ni,
    .req_i(data_req & d_sel_dmem), .we_i(data_we), .addr_i(data_addr - DMEM_BASE), .be_i(data_be),
    .wdata_i(data_wdata),
    .gnt_o(dm_gnt), .rvalid_o(dm_rvalid), .rdata_o(dm_rdata), .err_o(dm_err));

  // ------------------------------------------------------------------ MMIO
  logic        mm_gnt, mm_rvalid, mm_err;
  logic [31:0] mm_rdata;
  rv_obi_mmio u_mmio (
    .clk_i, .rst_ni, .req_i(data_req & d_sel_mmio), .we_i(data_we), .addr_i(data_addr),
    .wdata_i(data_wdata), .gnt_o(mm_gnt), .rvalid_o(mm_rvalid), .rdata_o(mm_rdata), .err_o(mm_err),
    .irq_software_o(irq_sw), .irq_timer_o(irq_tm), .irq_external_o(irq_ex),
    .tohost_valid_o, .tohost_o, .putchar_valid_o, .putchar_o, .roi_start_o, .roi_stop_o);

  // ------------------------------------------------------- error responders
  logic        ie_gnt, ie_rvalid, ie_err, de_gnt, de_rvalid, de_err;
  logic [31:0] ie_rdata, de_rdata;
  rv_obi_err u_err_i (.clk_i, .rst_ni, .req_i(instr_req & i_sel_err), .gnt_o(ie_gnt), .rvalid_o(ie_rvalid),
                      .rdata_o(ie_rdata), .err_o(ie_err));
  rv_obi_err u_err_d (.clk_i, .rst_ni, .req_i(data_req & d_sel_err), .gnt_o(de_gnt), .rvalid_o(de_rvalid),
                      .rdata_o(de_rdata), .err_o(de_err));

  // -------------------------------------------- merge the responses back to the core
  assign instr_gnt    = i_sel_imem ? im_i_gnt : ie_gnt;
  assign instr_rvalid = im_i_rvalid | ie_rvalid;
  assign instr_rdata  = ({32{im_i_rvalid}} & im_i_rdata) | ({32{ie_rvalid}} & ie_rdata);
  assign instr_err    = (im_i_rvalid & im_i_err) | (ie_rvalid & ie_err);

  assign data_gnt     = (d_sel_imem & im_d_gnt) | (d_sel_dmem & dm_gnt) | (d_sel_mmio & mm_gnt) | (d_sel_err & de_gnt);
  assign data_rvalid  = im_d_rvalid | dm_rvalid | mm_rvalid | de_rvalid;
  assign data_rdata   = ({32{im_d_rvalid}} & im_d_rdata) | ({32{dm_rvalid}} & dm_rdata) |
                        ({32{mm_rvalid}} & mm_rdata)     | ({32{de_rvalid}} & de_rdata);
  assign data_err     = (im_d_rvalid & im_d_err) | (dm_rvalid & dm_err) | (mm_rvalid & mm_err) | (de_rvalid & de_err);
endmodule
