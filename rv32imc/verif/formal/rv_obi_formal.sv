// -----------------------------------------------------------------------------
// rv_obi_formal.sv : formal harness. rv_core with a completely free but OBI-legal environment.
//   ASSUME (what any OBI 1.6 subordinate guarantees):  rvalid low in reset (R-2.2); a response only after its
//                request was granted in an EARLIER cycle (R-5); one response per granted request, in order (R-6);
//                gnt/err/rdata/irq are otherwise unconstrained (gnt may be high without req, R-3.2.1).
//   ASSERT (what the core owes as an OBI manager): req low in reset (R-2.1); address-phase signals stable and req
//                held until gnt (R-3.1.1, R-3.1.2); be non-zero & contiguous, addr[1:0] <= lowest be (R-7, R-9);
//                at most 2 outstanding instruction fetches and 1 outstanding data access (the core's own limits).
//   Rules written from the spec text (verif/obi_checker.sv has the simulation twin).
// -----------------------------------------------------------------------------
module rv_obi_formal #(
  parameter bit FAST_REDIRECT = 1'b0,
  parameter bit BP_ENABLE     = 1'b1,
  parameter bit ZICSR         = 1'b1,
  parameter bit OBI_STRICT_REQ = 1'b1
) (
  input  logic        clk,
  input  logic        rst_ni,
  input  logic        irq_sw, irq_tm, irq_ex,
  input  logic        instr_gnt, instr_rvalid, instr_err,
  input  logic [31:0] instr_rdata,
  input  logic        data_gnt, data_rvalid, data_err,
  input  logic [31:0] data_rdata
);
  logic        instr_req, data_req, data_we;
  logic [31:0] instr_addr, data_addr, data_wdata;
  logic [3:0]  data_be;
  logic        retire, ecall, ebreak, illegal, trap, mret;

  rv_core #(.FAST_REDIRECT(FAST_REDIRECT), .BP_ENABLE(BP_ENABLE), .ZICSR(ZICSR), .OBI_STRICT_REQ(OBI_STRICT_REQ),
            .BTB_N(2), .BTB_W(1), .BHT_N(4), .BHT_W(2), .RAS_N(2), .RAS_W(1)) dut (
    .clk_i(clk), .rst_ni, .boot_addr_i(32'h0000_0000), .hart_id_i(32'h0),
    .irq_software_i(irq_sw), .irq_timer_i(irq_tm), .irq_external_i(irq_ex),
    .instr_req_o(instr_req), .instr_gnt_i(instr_gnt), .instr_addr_o(instr_addr),
    .instr_rvalid_i(instr_rvalid), .instr_rdata_i(instr_rdata), .instr_err_i(instr_err),
    .data_req_o(data_req), .data_gnt_i(data_gnt), .data_addr_o(data_addr), .data_we_o(data_we),
    .data_be_o(data_be), .data_wdata_o(data_wdata), .data_rvalid_i(data_rvalid),
    .data_rdata_i(data_rdata), .data_err_i(data_err),
    .retire_o(retire), .ecall_o(ecall), .ebreak_o(ebreak), .illegal_o(illegal), .trap_o(trap), .mret_o(mret));

  // ---- reset sequence: held low for the first cycle, then released for good; boot address tied to 0 (reset value of the PC registers must be constant for the formal flow)
  logic init = 1'b1;
  always @(posedge clk) init <= 1'b0;
  always @(*) begin
    assume (rst_ni == !init);
  end

  // ---- outstanding-transaction bookkeeping (grants in earlier cycles minus responses so far)
  logic [2:0] oi = 3'd0;    // instruction
  logic [1:0] od = 2'd0;    // data
  logic       pr = 1'b0;    // previous cycle was after reset (history valid)
  logic       p_ireq, p_igr, p_dreq, p_dgr, p_dwe;
  logic [31:0] p_iaddr, p_daddr, p_dwdata;
  logic [3:0]  p_dbe;
  always @(posedge clk) begin
    pr      <= rst_ni;
    p_ireq  <= instr_req; p_igr <= instr_gnt; p_iaddr <= instr_addr;
    p_dreq  <= data_req;  p_dgr <= data_gnt;  p_daddr <= data_addr; p_dwe <= data_we; p_dbe <= data_be; p_dwdata <= data_wdata;
    if (!rst_ni) begin oi <= 3'd0; od <= 2'd0; end
    else begin
      oi <= oi + {2'b00, instr_req & instr_gnt} - {2'b00, instr_rvalid};
      od <= od + {1'b0, data_req & data_gnt} - {1'b0, data_rvalid};
    end
  end

  // ---- environment assumptions
  always @(*) begin
    if (!rst_ni) begin assume (!instr_rvalid); assume (!data_rvalid); end       // R-2.2
    assume (!instr_rvalid || oi != 3'd0);                                        // R-5 / R-6
    assume (!data_rvalid  || od != 2'd0);
  end

  // ---- manager obligations
  function logic be_ok(input logic [3:0] b);
    be_ok = b == 4'b0001 || b == 4'b0010 || b == 4'b0100 || b == 4'b1000 || b == 4'b0011 || b == 4'b0110 ||
            b == 4'b1100 || b == 4'b0111 || b == 4'b1110 || b == 4'b1111;
  endfunction
  function logic [1:0] lsb(input logic [3:0] b);
    lsb = b[0] ? 2'd0 : b[1] ? 2'd1 : b[2] ? 2'd2 : 2'd3;
  endfunction
  always @(*) begin
    if (!rst_ni) begin assert (!instr_req); assert (!data_req); end             // R-2.1
    if (pr && rst_ni) begin
      if (p_ireq && !p_igr) begin                                                // R-3.1.1 / R-3.1.2 (instruction)
        assert (instr_req);
        assert (instr_addr == p_iaddr);
      end
      if (p_dreq && !p_dgr) begin                                                // R-3.1.1 / R-3.1.2 (data)
        assert (data_req);
        assert (data_addr == p_daddr);
        assert (data_we == p_dwe);
        assert (data_be == p_dbe);
        assert (!data_we || (data_wdata & {{8{data_be[3]}}, {8{data_be[2]}}, {8{data_be[1]}}, {8{data_be[0]}}}) ==
                            (p_dwdata & {{8{p_dbe[3]}}, {8{p_dbe[2]}}, {8{p_dbe[1]}}, {8{p_dbe[0]}}}));
      end
    end
    if (rst_ni && data_req) begin assert (be_ok(data_be)); assert (data_addr[1:0] <= lsb(data_be)); end  // R-7 / R-9
    assert (oi <= 3'd2);                                                          // the core's own limits
    assert (od <= 2'd1);
  end
endmodule
