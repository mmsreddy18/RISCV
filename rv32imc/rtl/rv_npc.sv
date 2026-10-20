// -----------------------------------------------------------------------------
// rv_npc.sv : next-PC predictor = BTB + BHT (bimodal or gshare) + return-address stack
//
// Adapted from the biRISC-V front end (ultraembedded/biriscv, biriscv_npc.v):
//   * fully associative BTB, LFSR replacement
//   * BHT of 2-bit saturating counters, reset to "strongly taken"; optional gshare
//   * RAS with a speculative index (moved at prediction time) and a real index
//     (moved when the call/return is resolved in ID); a mispredict restores the
//     speculative index from the real one.
//
// Differences from biRISC-V, forced by this core's fetch (32-bit words + RVC):
//   * An entry is keyed by the address of the LAST HALFWORD of the branch (key =
//     pc + len - 2). The fetch stage looks up one word address per request, and
//     "the word that contains the last halfword" is the word after which the
//     fetch stream has to change direction.
//   * Entries carry only {cond, call, ret} flags. Unconditional jumps are always
//     predicted taken; conditional ones follow the BHT.
//   * A BTB entry is allocated only when a branch/jump is TAKEN; a not-taken
//     branch needs no entry, because sequential fetch is already right.
//   * Entries have valid bits (biRISC-V uses pc==0 as "empty").
//   * Training happens when the branch resolves in ID (id_issue), once per branch.
//
// When ENABLE = 0 the module outputs constants and the core behaves exactly like
// the version without a predictor.
// -----------------------------------------------------------------------------
module rv_npc #(
  parameter bit          ENABLE     = 1'b1,
  parameter int unsigned BTB_N      = 16,    // power of two
  parameter int unsigned BTB_W      = 4,     // log2(BTB_N)
  parameter int unsigned BHT_N      = 64,   // power of two
  parameter int unsigned BHT_W      = 6,     // log2(BHT_N)
  parameter int unsigned RAS_N      = 8,     // power of two
  parameter int unsigned RAS_W      = 3,     // log2(RAS_N)
  parameter bit          RAS_EN     = 1'b1,
  parameter bit          GSHARE     = 1'b0
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // ---- lookup, one aligned word per fetch request ----
  input  logic [31:0] lk_addr_i,       // word address of the request (bits [1:0] ignored)
  input  logic        lk_hw_i,         // 1: stream starts at the upper halfword of this word
  input  logic        lk_accept_i,     // request granted and belongs to the new stream
  output logic        pred_taken_o,    // a predicted-taken branch ends in this word
  output logic        pred_hw_o,       // ... its last halfword is the lower (0) / upper (1) one
  output logic [31:0] pred_target_o,
  output logic        pred_call_o,
  output logic        pred_ret_o,

  // ---- resolution of a branch/jump in ID ----
  input  logic        res_valid_i,     // a branch/jal/jalr issues this cycle
  input  logic [31:0] res_addr_i,      // address of its last halfword
  input  logic        res_taken_i,
  input  logic [31:0] res_target_i,    // actual target (valid when taken)
  input  logic        res_cond_i,      // conditional branch
  input  logic        res_call_i,
  input  logic        res_ret_i,
  input  logic        res_redirect_i   // ID redirects the fetch (any mispredict or flush)
);

  if (!ENABLE) begin : g_off
    assign pred_taken_o  = 1'b0;
    assign pred_hw_o     = 1'b0;
    assign pred_target_o = 32'h0;
    assign pred_call_o   = 1'b0;
    assign pred_ret_o    = 1'b0;
  end else begin : g_on

    // =========================================================================
    // Global history (gshare only)
    // =========================================================================
    logic [BHT_W-1:0] ghist_real_q, ghist_spec_q;
    logic [BHT_W-1:0] ghist_real_n, ghist_base;
    logic             hist_upd;                       // fetch-side shift this cycle

    assign ghist_real_n = (res_valid_i & res_cond_i) ? {ghist_real_q[BHT_W-2:0], res_taken_i}
                                                     : ghist_real_q;
    assign ghist_base   = res_redirect_i ? ghist_real_n : ghist_spec_q;

    // =========================================================================
    // BHT
    // =========================================================================
    logic [BHT_N-1:0][1:0] bht_q;

    function automatic logic [BHT_W-1:0] bht_idx(input logic [31:0] a, input logic [BHT_W-1:0] h);
      return a[BHT_W:1] ^ (GSHARE ? h : '0);
    endfunction

    logic [BHT_W-1:0] bht_wr_idx;
    assign bht_wr_idx = bht_idx(res_addr_i, ghist_real_q);

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        bht_q <= {BHT_N{2'd3}};
      end else if (res_valid_i & res_cond_i) begin
        if (res_taken_i  && bht_q[bht_wr_idx] != 2'd3) bht_q[bht_wr_idx] <= bht_q[bht_wr_idx] + 2'd1;
        if (!res_taken_i && bht_q[bht_wr_idx] != 2'd0) bht_q[bht_wr_idx] <= bht_q[bht_wr_idx] - 2'd1;
      end
    end

    // =========================================================================
    // BTB
    // =========================================================================
    logic [30:0] btb_key_q  [BTB_N];     // last-halfword address, bits [31:1]
    logic [31:0] btb_tgt_q  [BTB_N];
    logic        btb_cond_q [BTB_N];
    logic        btb_call_q [BTB_N];
    logic        btb_ret_q  [BTB_N];
    logic [BTB_N-1:0] btb_v_q;

    // ---- lookup: at most one entry for each of the two halfwords of the word ----
    logic        lo_hit, hi_hit, lo_cond, hi_cond, lo_call, hi_call, lo_ret, hi_ret;
    logic [31:0] lo_tgt, hi_tgt;

    always_comb begin
      lo_hit = 1'b0; lo_cond = 1'b0; lo_call = 1'b0; lo_ret = 1'b0; lo_tgt = '0;
      hi_hit = 1'b0; hi_cond = 1'b0; hi_call = 1'b0; hi_ret = 1'b0; hi_tgt = '0;
      for (int i = 0; i < BTB_N; i++) begin
        if (btb_v_q[i] && btb_key_q[i][30:1] == lk_addr_i[31:2]) begin
          if (!btb_key_q[i][0] && !lk_hw_i) begin      // lower halfword (skipped when the stream starts above it)
            lo_hit = 1'b1; lo_cond = btb_cond_q[i]; lo_call = btb_call_q[i];
            lo_ret = btb_ret_q[i]; lo_tgt = btb_tgt_q[i];
          end
          if (btb_key_q[i][0]) begin                   // upper halfword
            hi_hit = 1'b1; hi_cond = btb_cond_q[i]; hi_call = btb_call_q[i];
            hi_ret = btb_ret_q[i]; hi_tgt = btb_tgt_q[i];
          end
        end
      end
    end

    // ---- RAS (speculative index at fetch, real index at resolution) -------------
    logic [31:0]      ras_q   [RAS_N];
    logic [RAS_N-1:0] ras_v_q;
    logic [RAS_W-1:0] ras_idx_spec_q, ras_idx_real_q;
    logic [RAS_W-1:0] ras_idx_real_n, ras_base;
    logic [31:0]      ras_top;
    logic             ras_top_v;

    assign ras_idx_real_n = (res_valid_i & res_call_i) ? ras_idx_real_q + 1'b1 :
                            (res_valid_i & res_ret_i)  ? ras_idx_real_q - 1'b1 : ras_idx_real_q;
    assign ras_base       = res_redirect_i ? ras_idx_real_n : ras_idx_spec_q;

    // top of stack as seen by a lookup in this cycle (bypass the repair push)
    always_comb begin
      ras_top   = ras_q[ras_base];
      ras_top_v = ras_v_q[ras_base];
      if (res_redirect_i & res_valid_i & res_call_i) begin
        ras_top   = res_addr_i + 32'd2;
        ras_top_v = 1'b1;
      end
    end

    // ---- BHT lookup, choose the first predicted-taken entry in the word --------
    logic [1:0] lo_cnt, hi_cnt;
    logic       lo_tk, hi_tk;

    assign lo_cnt = bht_q[bht_idx({lk_addr_i[31:2], 2'b00}, ghist_base)];
    assign hi_cnt = bht_q[bht_idx({lk_addr_i[31:2], 2'b10}, ghist_base)];
    assign lo_tk  = lo_hit & (~lo_cond | lo_cnt[1]);
    assign hi_tk  = hi_hit & (~hi_cond | hi_cnt[1]);

    logic        c_call, c_ret, c_cond;
    logic [31:0] c_tgt, c_addr;
    always_comb begin
      pred_taken_o = lo_tk | hi_tk;
      pred_hw_o    = ~lo_tk;
      c_call = lo_tk ? lo_call : hi_call;
      c_ret  = lo_tk ? lo_ret  : hi_ret;
      c_cond = lo_tk ? lo_cond : hi_cond;
      c_tgt  = lo_tk ? lo_tgt  : hi_tgt;
      c_addr = {lk_addr_i[31:2], ~lo_tk, 1'b0};        // last-halfword address of the chosen branch
      pred_call_o   = pred_taken_o & c_call;
      pred_ret_o    = pred_taken_o & c_ret & RAS_EN;
      pred_target_o = (pred_ret_o && ras_top_v) ? ras_top : c_tgt;
      hist_upd      = pred_taken_o ? c_cond : ((lo_hit & lo_cond) | (hi_hit & hi_cond));
    end

    // ---- RAS / history sequential state ---------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        ras_idx_spec_q <= '0;
        ras_idx_real_q <= '0;
        ras_v_q        <= '0;
        ghist_real_q   <= '0;
        ghist_spec_q   <= '0;
      end else begin
        ras_idx_real_q <= ras_idx_real_n;
        ghist_real_q   <= ghist_real_n;

        // repair: a call that had to redirect (not predicted) is pushed now
        if (res_redirect_i & res_valid_i & res_call_i)
          ras_v_q[ras_idx_real_n] <= 1'b1;

        ras_idx_spec_q <= ras_base;
        if (lk_accept_i && RAS_EN) begin
          if (pred_call_o) begin
            ras_idx_spec_q          <= ras_base + 1'b1;
            ras_v_q[ras_base + 1'b1]<= 1'b1;
          end else if (pred_ret_o) begin
            ras_idx_spec_q          <= ras_base - 1'b1;
          end
        end

        ghist_spec_q <= ghist_base;
        if (lk_accept_i && hist_upd) ghist_spec_q <= {ghist_base[BHT_W-2:0], pred_taken_o};
      end
    end

    // RAS data (no reset: ras_v_q says what is valid). The speculative push is
    // written last, so it wins if both land on the same entry.
    always_ff @(posedge clk_i) begin
      if (res_redirect_i & res_valid_i & res_call_i)
        ras_q[ras_idx_real_n] <= res_addr_i + 32'd2;
      if (lk_accept_i && RAS_EN && pred_call_o)
        ras_q[ras_base + 1'b1] <= c_addr + 32'd2;
    end

    // ---- BTB training -------------------------------------------------------------
    logic [BTB_N-1:0] t_match;
    logic             t_hit;
    logic [BTB_W-1:0] t_idx, alloc_idx;
    logic [15:0]      lfsr_q;

    always_comb begin
      t_hit = 1'b0;
      t_idx = '0;
      for (int i = 0; i < BTB_N; i++) begin
        t_match[i] = btb_v_q[i] && (btb_key_q[i] == res_addr_i[31:1]);
        if (t_match[i]) begin t_hit = 1'b1; t_idx = BTB_W'(i); end
      end
    end

    assign alloc_idx = lfsr_q[BTB_W-1:0];

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        btb_v_q <= '0;
        lfsr_q  <= 16'h0001;
      end else if (res_valid_i && !t_hit && res_taken_i) begin
        btb_v_q[alloc_idx] <= 1'b1;
        lfsr_q <= lfsr_q[0] ? ({1'b0, lfsr_q[15:1]} ^ 16'hB400) : {1'b0, lfsr_q[15:1]};
      end
    end

    // BTB data (no reset: btb_v_q says what is valid)
    always_ff @(posedge clk_i) begin
      if (res_valid_i) begin
        if (t_hit) begin
          btb_cond_q[t_idx] <= res_cond_i;
          btb_call_q[t_idx] <= res_call_i;
          btb_ret_q [t_idx] <= res_ret_i;
          if (res_taken_i) btb_tgt_q[t_idx] <= res_target_i;
        end else if (res_taken_i) begin
          btb_key_q[alloc_idx]  <= res_addr_i[31:1];
          btb_tgt_q[alloc_idx]  <= res_target_i;
          btb_cond_q[alloc_idx] <= res_cond_i;
          btb_call_q[alloc_idx] <= res_call_i;
          btb_ret_q[alloc_idx]  <= res_ret_i;
        end
      end
    end

  end

endmodule
