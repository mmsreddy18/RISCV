// -----------------------------------------------------------------------------
// rv_fetch.sv : IF stage = prefetch FIFO + halfword aligner + RVC expander
//
//  * Fetches aligned 32-bit words over an OBI-style port (req/gnt, rvalid).
//    Up to 2 requests may be in flight; on a redirect, responses still in
//    flight are counted as "stale" and silently dropped when they return.
//  * Words are queued in a DEPTH-entry FIFO. The aligner looks at the two head
//    words and a halfword offset, so 32-bit instructions that straddle a word
//    boundary and 16-bit instructions are delivered one per cycle.
//  * Output (instr_valid_o/instr_ready_i) is a plain valid/ready handshake to
//    the IF/ID register in rv_core.
//
//  * Branch prediction (rv_npc: BTB + BHT + RAS, adapted from biRISC-V): each
//    word request is looked up by address. If a predicted-taken branch ends in the
//    word, the NEXT request goes straight to the predicted target (no bubble in the
//    request stream). The word is tagged {taken, halfword, target, call, ret}; the
//    tag rides with the response into the FIFO. When the aligner delivers the
//    instruction whose last halfword is the tagged one, it (a) hands the prediction
//    to ID for verification, (b) drops the rest of that word and (c) continues at
//    the target. A wrong prediction is repaired by ID through the normal redirect.
//
//  OBI compliance (OBI 1.6.0 R-2.1, R-3.1.1, R-3.1.2): req is low during reset, and
//  once req is asserted it stays asserted with the SAME address until gnt. If a
//  redirect arrives while such a request is waiting for gnt, the request is held
//  (pend_q / pend_addr_q), marked stale (its response is dropped) and the fetch of the
//  new stream starts only after it has been granted. With zero-wait grants this never
//  happens, so cycle counts are unchanged.
// -----------------------------------------------------------------------------
module rv_fetch #(
  parameter int unsigned DEPTH         = 4,   // must be a power of two, >= 2
  // 1: the fetch of the branch target is requested in the SAME cycle the branch is
  //    resolved in ID (taken-branch penalty 2 instead of 3 cycles), at the cost of
  //    a combinational path  ID compare/target -> instr_req_o/instr_addr_o  (and
  //    from data_gnt_i/data_rvalid_i through the issue logic). Beware of shared
  //    memory fabrics where data_gnt can depend combinationally on instr_req.
  parameter bit          FAST_REDIRECT = 1'b0,
  // branch prediction (see rv_npc.sv)
  parameter bit          BP_ENABLE  = 1'b1,
  parameter int unsigned BTB_N      = 16,
  parameter int unsigned BTB_W      = 4,
  parameter int unsigned BHT_N      = 64,
  parameter int unsigned BHT_W      = 6,
  parameter int unsigned RAS_N      = 8,
  parameter int unsigned RAS_W      = 3,
  parameter bit          GSHARE     = 1'b0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [31:0] boot_addr_i,

  // redirect from ID (taken branch / jump)
  input  logic        redirect_i,
  input  logic [31:0] redirect_pc_i,

  // branch resolution in ID, used to train the predictor
  input  logic        res_valid_i,
  input  logic [31:0] res_addr_i,        // address of the last halfword of the branch
  input  logic        res_taken_i,
  input  logic [31:0] res_target_i,
  input  logic        res_cond_i,
  input  logic        res_call_i,
  input  logic        res_ret_i,

  // instruction memory port
  output logic        instr_req_o,
  input  logic        instr_gnt_i,
  output logic [31:0] instr_addr_o,
  input  logic        instr_rvalid_i,
  input  logic [31:0] instr_rdata_i,
  input  logic        instr_err_i,         // OBI err: the response word is an access fault

  // to ID
  output logic        instr_valid_o,
  input  logic        instr_ready_i,
  output logic [31:0] instr_o,             // already expanded to 32 bit
  output logic [31:0] pc_o,
  output logic        is_compressed_o,
  output logic        pred_taken_o,        // this instruction was predicted taken ...
  output logic [31:0] pred_target_o,       // ... to this target
  output logic        pred_call_o,
  output logic        pred_ret_o,
  output logic        instr_err_o,         // the head instruction touches a word that returned err
  output logic        instr_err_hi_o       // ... only its upper half (32-bit instruction straddling words)
);

  localparam int unsigned PTR_W = $clog2(DEPTH);

  logic [31:0]      fifo_q [DEPTH];
  logic [PTR_W-1:0] rd_ptr_q, wr_ptr_q;
  logic [PTR_W:0]   count_q;

  logic [31:0] fetch_addr_q;     // next word address to request
  logic [31:0] pc_q;             // PC of the instruction at the FIFO head
  logic        hw_off_q;         // head instruction starts in the upper halfword
  logic [1:0]  inflight_q;       // granted requests with no response yet
  logic [1:0]  stale_q;          // oldest N responses must be dropped
  logic        fetch_hw_q;       // the stream starts at the upper halfword of fetch_addr_q

  // prediction tag of a word: {taken, last-halfword, target, call, ret}
  typedef struct packed {
    logic        pt;
    logic        hw;
    logic        call;
    logic        ret;
    logic [31:0] tgt;
  } tag_t;
  tag_t tag_fifo_q [DEPTH];
  tag_t tagq_q [2];              // tags of the requests in flight, oldest first
  tag_t tag_new;

  // ---------------------------------------------------------------- requests
  logic [31:0] redirect_word;
  assign redirect_word = {redirect_pc_i[31:2], 2'b00};

  logic        req_n;           // the request the fetch logic would like to make
  logic [31:0] addr_n;
  logic        pend_q;          // a request was asserted last cycle and not granted
  logic        pend_stale_q;    // ... and a redirect has happened since (old stream)
  logic [31:0] pend_addr_q;

  generate
    if (FAST_REDIRECT) begin : g_fast
      // FIFO is flushed by the redirect, so only the in-flight limit matters.
      assign req_n  = redirect_i ? (inflight_q < 2'd2)
                                 : ((int'(count_q) + int'(inflight_q) < DEPTH) && (inflight_q < 2'd2));
      assign addr_n = redirect_i ? redirect_word : fetch_addr_q;
    end else begin : g_slow
      assign req_n  = (int'(count_q) + int'(inflight_q) < DEPTH) && (inflight_q < 2'd2);
      assign addr_n = fetch_addr_q;
    end
  endgenerate

  // hold an ungranted request unchanged (OBI R-3.1.1 / R-3.1.2); no request during reset (R-2.1)
  assign instr_req_o  = rst_ni & (pend_q | req_n);
  assign instr_addr_o = pend_q ? pend_addr_q : addr_n;

  logic req_gnt, resp_push, resp_drop;
  assign req_gnt   = instr_req_o & instr_gnt_i;
  // a held request that belongs to the old stream and is granted now: it only needs its
  // response dropped; it must not move fetch_addr_q or train / look up the predictor
  logic stale_gnt, fast_stale_gnt;
  assign stale_gnt      = req_gnt & pend_q & pend_stale_q;
  assign fast_stale_gnt = FAST_REDIRECT & redirect_i & req_gnt & pend_q & ~pend_stale_q;
  assign resp_push = instr_rvalid_i & (stale_q == 2'd0);
  assign resp_drop = instr_rvalid_i & (stale_q != 2'd0);

  // ------------------------------------------------------------------ predictor
  logic        np_taken, np_hw, np_call, np_ret, lk_accept;
  logic [31:0] np_target;
  logic        lk_hw;

  assign lk_accept = req_gnt & (FAST_REDIRECT | ~redirect_i) & ~stale_gnt & ~fast_stale_gnt;
  assign lk_hw     = (FAST_REDIRECT & redirect_i) ? redirect_pc_i[1] : fetch_hw_q;

  rv_npc #(
    .ENABLE(BP_ENABLE), .BTB_N(BTB_N), .BTB_W(BTB_W), .BHT_N(BHT_N), .BHT_W(BHT_W),
    .RAS_N(RAS_N), .RAS_W(RAS_W), .GSHARE(GSHARE)
  ) u_npc (
    .clk_i, .rst_ni,
    .lk_addr_i     (instr_addr_o),
    .lk_hw_i       (lk_hw),
    .lk_accept_i   (lk_accept),
    .pred_taken_o  (np_taken),
    .pred_hw_o     (np_hw),
    .pred_target_o (np_target),
    .pred_call_o   (np_call),
    .pred_ret_o    (np_ret),
    .res_valid_i, .res_addr_i, .res_taken_i, .res_target_i,
    .res_cond_i, .res_call_i, .res_ret_i,
    .res_redirect_i(redirect_i)
  );

  assign tag_new = '{pt: np_taken & lk_accept, hw: np_hw, call: np_call, ret: np_ret, tgt: np_target};

  logic [31:0] np_word;
  assign np_word = {np_target[31:2], 2'b00};

  logic [1:0] inflight_old_d, inflight_d;
  assign inflight_old_d = inflight_q - {1'b0, instr_rvalid_i};         // old-stream requests left
  assign inflight_d     = inflight_old_d + {1'b0, req_gnt};

  // ----------------------------------------------------------------- aligner
  logic [31:0] w0, w1, raw32, exp_instr;
  logic [15:0] lo16;
  logic        v0, v1, is_c, avail, exp_illegal;

  assign w0   = fifo_q[rd_ptr_q];
  assign w1   = fifo_q[PTR_W'(rd_ptr_q + 1'b1)];
  assign v0   = (count_q >= 1);
  assign v1   = (count_q >= 2);

  assign lo16  = hw_off_q ? w0[31:16] : w0[15:0];
  assign is_c  = (lo16[1:0] != 2'b11);
  assign raw32 = hw_off_q ? {w1[15:0], w0[31:16]} : w0;
  assign avail = is_c ? v0 : (hw_off_q ? (v0 & v1) : v0);

  rv_c_decoder u_cdec (
    .instr_i   (lo16),
    .instr_o   (exp_instr),
    .illegal_o (exp_illegal)
  );

  logic [DEPTH-1:0] err_fifo_q;      // err flag of each FIFO word (qualified by count_q)
  logic             err0, err1;
  assign err0 = err_fifo_q[rd_ptr_q];
  assign err1 = err_fifo_q[PTR_W'(rd_ptr_q + 1'b1)];
  assign instr_err_o    = avail & (err0 | ((!is_c && hw_off_q) & err1));
  assign instr_err_hi_o = (!is_c && hw_off_q) & ~err0;

  assign instr_valid_o   = avail;
  assign instr_o         = is_c ? exp_instr : raw32;
  assign pc_o            = pc_q;
  assign is_compressed_o = is_c;

  // the word holding the last halfword of the head instruction, and which halfword
  logic [PTR_W-1:0] e_idx;
  logic             e_hw, e_pt;
  tag_t             e_tag;
  assign e_idx = (!is_c && hw_off_q) ? PTR_W'(rd_ptr_q + 1'b1) : rd_ptr_q;
  assign e_hw  = is_c ? hw_off_q : ~hw_off_q;
  assign e_tag = tag_fifo_q[e_idx];
  assign e_pt  = BP_ENABLE & e_tag.pt & (e_tag.hw == e_hw);   // BP_ENABLE=0: all tag logic is dead

  assign pred_taken_o  = e_pt;
  assign pred_target_o = e_tag.tgt;
  assign pred_call_o   = e_pt & e_tag.call;
  assign pred_ret_o    = e_pt & e_tag.ret;

  logic consume, pop, take;
  logic [1:0] npop;
  assign consume = avail & instr_ready_i;
  assign take    = consume & e_pt;                       // predicted-taken instruction leaves
  assign pop     = consume & (is_c ? hw_off_q : 1'b1);
  // a taken instruction also drops the rest of its word (and a straddled first word)
  assign npop    = take ? ((!is_c && hw_off_q) ? 2'd2 : 2'd1) : {1'b0, pop};

  // -------------------------------------------------------------- sequential
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fetch_addr_q <= {boot_addr_i[31:2], 2'b00};
      pc_q         <= {boot_addr_i[31:1], 1'b0};
      hw_off_q     <= boot_addr_i[1];
      rd_ptr_q     <= '0;
      wr_ptr_q     <= '0;
      count_q      <= '0;
      inflight_q   <= '0;
      stale_q      <= '0;
      fetch_hw_q   <= boot_addr_i[1];
      pend_q       <= 1'b0;
      pend_stale_q <= 1'b0;
    end else begin
      inflight_q <= inflight_d;

      // ungranted-request tracking (OBI hold-until-gnt)
      pend_q <= instr_req_o & ~instr_gnt_i;
      if (instr_gnt_i | ~instr_req_o) pend_stale_q <= 1'b0;
      else pend_stale_q <= (pend_q & pend_stale_q) | (redirect_i & (pend_q | ~FAST_REDIRECT));

      if (redirect_i) begin
        // Everything still in flight belongs to the old stream. In FAST mode a request
        // granted this cycle already targets the new stream and is not stale.
        stale_q      <= FAST_REDIRECT ? (inflight_old_d + {1'b0, fast_stale_gnt}) : inflight_d;
        if (FAST_REDIRECT && req_gnt && !pend_q) begin
          fetch_addr_q <= np_taken ? np_word : (redirect_word + 32'd4);
          fetch_hw_q   <= np_taken & np_target[1];
        end else begin
          fetch_addr_q <= redirect_word;
          fetch_hw_q   <= redirect_pc_i[1];
        end
        pc_q         <= {redirect_pc_i[31:1], 1'b0};
        hw_off_q     <= redirect_pc_i[1];
        rd_ptr_q     <= '0;
        wr_ptr_q     <= '0;
        count_q      <= '0;
      end else begin
        stale_q <= stale_q - {1'b0, resp_drop} + {1'b0, stale_gnt};
        if (req_gnt && !stale_gnt) begin
          fetch_addr_q <= np_taken ? np_word : (fetch_addr_q + 32'd4);
          fetch_hw_q   <= np_taken & np_target[1];
        end

        if (resp_push) begin
          fifo_q[wr_ptr_q] <= instr_rdata_i;
          wr_ptr_q         <= wr_ptr_q + 1'b1;
        end
        rd_ptr_q <= rd_ptr_q + PTR_W'(npop);
        count_q  <= count_q + (PTR_W+1)'(resp_push) - (PTR_W+1)'(npop);

        if (take) begin
          pc_q     <= e_tag.tgt;
          hw_off_q <= e_tag.tgt[1];
        end else if (consume) begin
          pc_q <= pc_q + (is_c ? 32'd2 : 32'd4);
          if (is_c) hw_off_q <= ~hw_off_q;
        end
      end
    end
  end


  // tag storage: FIFO words and the requests in flight (no reset needed; qualified by
  // count_q / inflight_q)
  always_ff @(posedge clk_i) begin
    pend_addr_q <= instr_addr_o;     // address of the request being offered (held while pend_q)
    if (resp_push) tag_fifo_q[wr_ptr_q] <= tagq_q[0];
    if (resp_push) err_fifo_q[wr_ptr_q] <= instr_err_i;

    // in-flight queue: response pops the oldest, a granted request pushes behind the rest
    if (instr_rvalid_i) tagq_q[0] <= tagq_q[1];
    if (req_gnt) begin
      if (inflight_q - {1'b0, instr_rvalid_i} == 2'd0) tagq_q[0] <= tag_new;
      else                                              tagq_q[1] <= tag_new;
    end
  end

endmodule
