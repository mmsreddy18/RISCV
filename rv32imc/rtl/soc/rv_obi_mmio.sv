// -----------------------------------------------------------------------------
// rv_obi_mmio.sv : memory-mapped peripherals (word accesses), gnt always 1, rvalid 1 cycle later.
//   0x000 W  tohost   (test result, pulses tohost_valid_o)      0x004 W putchar
//   0x008 W  ROI start pulse                                    0x00C W ROI stop pulse
//   0x010 RW software-interrupt line (bit0)                     0x014 RW external-interrupt line (bit0)
//   0x018 W  one-shot timer: store N -> timer irq after N cycles (0 clears)
//   0x100 RW mtime[31:0]  0x104 RW mtime[63:32]  0x108 RW mtimecmp[31:0]  0x10C RW mtimecmp[63:32]
//   timer irq = one-shot | (mtime >= mtimecmp)   (mtimecmp resets to all ones)
//   any other offset: err=1 (access fault)
// -----------------------------------------------------------------------------
module rv_obi_mmio (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        req_i,
  input  logic        we_i,
  input  logic [31:0] addr_i,
  input  logic [31:0] wdata_i,
  output logic        gnt_o,
  output logic        rvalid_o,
  output logic [31:0] rdata_o,
  output logic        err_o,
  output logic        irq_software_o,
  output logic        irq_timer_o,
  output logic        irq_external_o,
  output logic        tohost_valid_o,
  output logic [31:0] tohost_o,
  output logic        putchar_valid_o,
  output logic [7:0]  putchar_o,
  output logic        roi_start_o,
  output logic        roi_stop_o
);
  logic [63:0] mtime_q, mtimecmp_q;
  logic        sw_q, ext_q, oneshot_q;
  logic [31:0] oneshot_cnt_q, tohost_q;
  logic [11:0] off;
  logic        acc, hit_w, hit_r;
  assign gnt_o = 1'b1;
  assign off   = addr_i[11:0];
  assign acc   = req_i;

  always_comb begin
    hit_r = 1'b1; hit_w = 1'b1;
    unique case (off)
      12'h000: begin hit_r = 1'b1; hit_w = 1'b1; end
      12'h004, 12'h008, 12'h00C, 12'h018: begin hit_r = 1'b0; hit_w = 1'b1; end
      12'h010, 12'h014, 12'h100, 12'h104, 12'h108, 12'h10C: ;
      default: begin hit_r = 1'b0; hit_w = 1'b0; end
    endcase
  end

  assign irq_software_o = sw_q;
  assign irq_external_o = ext_q;
  assign irq_timer_o    = oneshot_q | (mtime_q >= mtimecmp_q);
  assign tohost_o       = tohost_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mtime_q <= '0; mtimecmp_q <= '1; sw_q <= 1'b0; ext_q <= 1'b0; oneshot_q <= 1'b0;
      oneshot_cnt_q <= '0; tohost_q <= '0;
      rvalid_o <= 1'b0; err_o <= 1'b0; rdata_o <= '0;
      tohost_valid_o <= 1'b0; putchar_valid_o <= 1'b0; putchar_o <= '0; roi_start_o <= 1'b0; roi_stop_o <= 1'b0;
    end else begin
      mtime_q <= mtime_q + 64'd1;
      tohost_valid_o <= 1'b0; putchar_valid_o <= 1'b0; roi_start_o <= 1'b0; roi_stop_o <= 1'b0;
      if (oneshot_cnt_q != 0) begin
        oneshot_cnt_q <= oneshot_cnt_q - 1;
        if (oneshot_cnt_q == 1) oneshot_q <= 1'b1;
      end
      rvalid_o <= acc;
      err_o    <= acc & (we_i ? ~hit_w : ~hit_r);
      if (acc && !we_i) begin
        unique case (off)
          12'h000: rdata_o <= tohost_q;
          12'h010: rdata_o <= {31'h0, sw_q};
          12'h014: rdata_o <= {31'h0, ext_q};
          12'h100: rdata_o <= mtime_q[31:0];
          12'h104: rdata_o <= mtime_q[63:32];
          12'h108: rdata_o <= mtimecmp_q[31:0];
          12'h10C: rdata_o <= mtimecmp_q[63:32];
          default: rdata_o <= '0;
        endcase
      end
      if (acc && we_i) begin
        unique case (off)
          12'h000: begin tohost_q <= wdata_i; tohost_valid_o <= 1'b1; end
          12'h004: begin putchar_o <= wdata_i[7:0]; putchar_valid_o <= 1'b1; end
          12'h008: roi_start_o <= 1'b1;
          12'h00C: roi_stop_o  <= 1'b1;
          12'h010: sw_q  <= wdata_i[0];
          12'h014: ext_q <= wdata_i[0];
          12'h018: begin oneshot_q <= 1'b0; oneshot_cnt_q <= wdata_i; end
          12'h100: mtime_q[31:0]      <= wdata_i;
          12'h104: mtime_q[63:32]     <= wdata_i;
          12'h108: mtimecmp_q[31:0]   <= wdata_i;
          12'h10C: mtimecmp_q[63:32]  <= wdata_i;
          default: ;
        endcase
      end
    end
  end
endmodule
