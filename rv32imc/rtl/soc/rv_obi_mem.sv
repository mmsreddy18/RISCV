// -----------------------------------------------------------------------------
// rv_obi_mem.sv : one on-chip SRAM as an OBI subordinate = [obi_cut x CUTS] -> obi_sram_shim -> rv_sram_array
//   (the shim is the unmodified pulp-platform/obi block). Used twice by rv_soc: instruction and data memory.
//   BASE_WORD / IMG_WORDS: where this memory's initial contents sit inside the +hex image (word index).
// -----------------------------------------------------------------------------
module rv_obi_mem #(
  parameter obi_pkg::obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig,
  parameter type         obi_a_chan_t = logic,
  parameter type         obi_r_chan_t = logic,
  parameter type         obi_req_t    = logic,
  parameter type         obi_rsp_t    = logic,
  parameter int unsigned WORDS        = 32768,
  parameter int unsigned BASE_WORD    = 0,
  parameter int unsigned IMG_WORDS    = 65536,
  parameter bit          STALL        = 1'b0,
  parameter int unsigned CUTS         = 0
) (
  input  logic     clk_i,
  input  logic     rst_ni,
  input  obi_req_t req_i,
  output obi_rsp_t rsp_o
);
  obi_req_t sram_req; obi_rsp_t sram_rsp;
  if (CUTS == 0) begin : g_nocut
    assign sram_req = req_i;
    assign rsp_o    = sram_rsp;
  end else begin : g_cut
    obi_req_t [CUTS:0] creq; obi_rsp_t [CUTS:0] crsp;
    assign creq[0] = req_i;
    assign rsp_o   = crsp[0];
    for (genvar i = 0; i < CUTS; i++) begin : g_c
      obi_cut #(.ObiCfg(ObiCfg), .obi_a_chan_t(obi_a_chan_t), .obi_r_chan_t(obi_r_chan_t),
                .obi_req_t(obi_req_t), .obi_rsp_t(obi_rsp_t)) u_cut (
        .clk_i, .rst_ni,
        .sbr_port_req_i(creq[i]), .sbr_port_rsp_o(crsp[i]),
        .mgr_port_req_o(creq[i+1]), .mgr_port_rsp_i(crsp[i+1]));
    end
    assign sram_req        = creq[CUTS];
    assign crsp[CUTS]      = sram_rsp;
  end
  logic        s_req, s_we, s_gnt; logic [31:0] s_addr, s_wdata, s_rdata; logic [3:0] s_be;
  obi_sram_shim #(.ObiCfg(ObiCfg), .obi_req_t(obi_req_t), .obi_rsp_t(obi_rsp_t)) u_shim (
    .clk_i, .rst_ni, .obi_req_i(sram_req), .obi_rsp_o(sram_rsp),
    .req_o(s_req), .we_o(s_we), .addr_o(s_addr), .wdata_o(s_wdata), .be_o(s_be), .gnt_i(s_gnt), .rdata_i(s_rdata));
  rv_sram_array #(.WORDS(WORDS), .BASE_WORD(BASE_WORD), .IMG_WORDS(IMG_WORDS), .STALL(STALL)) u_arr (
    .clk_i, .rst_ni, .req_i(s_req), .we_i(s_we), .addr_i(s_addr), .wdata_i(s_wdata), .be_i(s_be),
    .gnt_o(s_gnt), .rdata_o(s_rdata));
endmodule
