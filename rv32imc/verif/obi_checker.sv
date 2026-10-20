// -----------------------------------------------------------------------------
// obi_checker.sv : OBI 1.6.0 protocol checker (rule IDs are those of the OBI spec,
//                  openhwgroup/obi OBI-v1.6.0.pdf, section 3.3 / 3.4).
//
// Written from the spec text, NOT from the core. Immediate assertions with explicit
// history registers, so it works in Verilator and in Yosys/SymbiYosys alike.
//
//   Manager-side rules (the core must satisfy them)
//     R-2.1    req low while reset is asserted
//     R-3.1.1  address-phase signals (addr, we, be, wdata[be]) stable until gnt
//     R-3.1.2  req not de-asserted before the address phase ends (gnt)
//     R-7      (data port, BE_FULL=0) be != 0 and the 1s are contiguous
//     R-9      addr[1:0] <= index of the least significant set be bit
//   Subordinate-side rules (the memory / interconnect must satisfy them)
//     R-2.2    rvalid low while reset is asserted
//     R-5      rvalid only after the matching req&gnt was sampled (no response w/o request)
//
//   FATAL=1 : $fatal at the first violation (regression)   FATAL=0 : count and report (audit)
//   MGR / SUB select which side's rules are asserted (the other side's are skipped).
// -----------------------------------------------------------------------------
module obi_checker #(
  parameter string NAME  = "obi",
  parameter bit    DATA  = 1'b1,    // 1 = data port (we/be/wdata present), 0 = instruction port
  parameter bit    MGR   = 1'b1,
  parameter bit    SUB   = 1'b1,
  parameter bit    FATAL = 1'b0
) (
  input logic        clk_i,
  input logic        rst_ni,
  input logic        req_i,
  input logic        gnt_i,
  input logic [31:0] addr_i,
  input logic        we_i,
  input logic [3:0]  be_i,
  input logic [31:0] wdata_i,
  input logic        rvalid_i
);
  localparam int NR = 7;
  string rname [NR] = '{"R-2.1","R-3.1.1(addr)","R-3.1.1(we/be/wdata)","R-3.1.2","R-7/R-9","R-2.2","R-5"};
  int unsigned vcount [NR];
  int unsigned outstanding;
  logic        p_req, p_gnt, p_we, p_rst;
  logic [31:0] p_addr, p_wdata;
  logic [3:0]  p_be;

  function automatic logic be_ok(input logic [3:0] b);
    // non-zero, contiguous ones
    case (b)
      4'b0001, 4'b0010, 4'b0100, 4'b1000, 4'b0011, 4'b0110, 4'b1100,
      4'b0111, 4'b1110, 4'b1111: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction
  function automatic logic addr_be_ok(input logic [1:0] a, input logic [3:0] b);
    logic [1:0] lsb;
    lsb = b[0] ? 2'd0 : b[1] ? 2'd1 : b[2] ? 2'd2 : 2'd3;
    return a <= lsb;
  endfunction

  task automatic fail(input int r, input string msg);
    vcount[r]++;
    if (vcount[r] <= 3)
      $display("OBI-CHK[%s] VIOLATION %s: %s  (t=%0t)", NAME, rname[r], msg, $time);
    if (FATAL) $fatal(1, "OBI-CHK[%s] %s", NAME, rname[r]);
  endtask

  initial begin
    for (int i = 0; i < NR; i++) vcount[i] = 0;
    outstanding = 0;
    p_req = 0; p_gnt = 0; p_rst = 0; p_we = 0; p_addr = '0; p_wdata = '0; p_be = '0;
  end

  always @(posedge clk_i) begin
    if (!rst_ni) begin
      if (MGR && req_i)    fail(0, "req high during reset");
      if (SUB && rvalid_i) fail(5, "rvalid high during reset");
      outstanding = 0;
    end else begin
      // ---- manager side
      if (MGR) begin
        if (p_req && !p_gnt && p_rst) begin
          if (!req_i)             fail(3, "req de-asserted before gnt");
          else begin
            if (addr_i != p_addr) fail(1, $sformatf("addr changed %08x -> %08x before gnt", p_addr, addr_i));
            if (DATA) begin
              if (we_i != p_we || be_i != p_be) fail(2, "we/be changed before gnt");
              else if (we_i && ((wdata_i ^ p_wdata) &
                       {{8{be_i[3]}}, {8{be_i[2]}}, {8{be_i[1]}}, {8{be_i[0]}}}) != 0)
                fail(2, "wdata changed before gnt");
            end
          end
        end
        if (req_i && DATA) begin
          if (!be_ok(be_i) || !addr_be_ok(addr_i[1:0], be_i))
            fail(4, $sformatf("be=%b addr[1:0]=%0d", be_i, addr_i[1:0]));
        end
      end
      // ---- subordinate side
      if (SUB && rvalid_i && outstanding == 0) fail(6, "rvalid with no granted request outstanding");
      // ---- bookkeeping
      outstanding = outstanding + ((req_i && gnt_i) ? 1 : 0) - ((rvalid_i && outstanding != 0) ? 1 : 0);
    end
    p_rst <= rst_ni; p_req <= req_i; p_gnt <= gnt_i; p_addr <= addr_i;
    p_we <= we_i; p_be <= be_i; p_wdata <= wdata_i;
  end

  function automatic int unsigned total();
    int unsigned t = 0;
    for (int i = 0; i < NR; i++) t += vcount[i];
    return t;
  endfunction

  final begin
    $display("OBI-CHK[%s] summary:", NAME);
    for (int i = 0; i < NR; i++)
      $display("   %-22s %0d violation(s)", rname[i], vcount[i]);
  end
endmodule
