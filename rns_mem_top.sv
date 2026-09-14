module rns_mem_top #(
    parameter int N        = 5,
    parameter int H        = 32,
    parameter int W        = 32,
    parameter int CIN      = 3,
    parameter int COUT     = 64,     // SET from conv1_weight.shape[0]
    parameter int KH       = 3,
    parameter int KW       = 3,
    parameter int PAD      = 1,
    parameter int STRIDE   = 1,
    parameter int IFMAP_BIN_WIDTH = 16,
    parameter int MUL_EXT_BITS    = 3,

    parameter string IFMAP_MEM_FILE = "ifmap.mem",
    parameter string W_R31_MEM_FILE = "weight_r31.mem",
    parameter string W_R32_MEM_FILE = "weight_r32.mem",
    parameter string W_R63_MEM_FILE = "weight_r63.mem"
)(
    input  logic clk,
    input  logic rst_n,
    input  logic run,
    output logic layer_done
);

  localparam int OH = (H + 2*PAD - KH) / STRIDE + 1;
  localparam int OW = (W + 2*PAD - KW) / STRIDE + 1;

  localparam int IFMAP_DEPTH  = CIN * H * W;
  localparam int WEIGHT_DEPTH = COUT * CIN * KH * KW;
  localparam int OUT_DEPTH    = COUT * OH * OW;

  // ---------------------------------------------------------------
  // Ifmap memory (BNS), zero-forced on !ren
  // ---------------------------------------------------------------
  logic [IFMAP_BIN_WIDTH-1:0] ifmap_mem [IFMAP_DEPTH];
  initial $readmemh(IFMAP_MEM_FILE, ifmap_mem);

  logic                       ifmap_ren_w;
  logic [$clog2(IFMAP_DEPTH)-1:0] ifmap_addr_w;
  logic                       ifmap_ren_q;
  logic [IFMAP_BIN_WIDTH-1:0] ifmap_rdata_q;

  always_ff @(posedge clk) begin
    ifmap_ren_q   <= ifmap_ren_w;
    ifmap_rdata_q <= ifmap_mem[ifmap_addr_w];   // read every cycle; qualified by ren below
  end

  wire [IFMAP_BIN_WIDTH-1:0] ifmap_rdata = ifmap_ren_q ? ifmap_rdata_q : '0;

  // ---------------------------------------------------------------
  // Weight memories (pre-converted RNS residues)
  // ---------------------------------------------------------------
  logic [N-1:0] w_r31_mem [WEIGHT_DEPTH];
  logic [N-1:0] w_r32_mem [WEIGHT_DEPTH];
  logic [N:0]   w_r63_mem [WEIGHT_DEPTH];
  initial $readmemh(W_R31_MEM_FILE, w_r31_mem);
  initial $readmemh(W_R32_MEM_FILE, w_r32_mem);
  initial $readmemh(W_R63_MEM_FILE, w_r63_mem);

  logic [$clog2(WEIGHT_DEPTH)-1:0] weight_addr_w;
  logic [N-1:0] w_r31_q, w_r32_q;
  logic [N:0]   w_r63_q;

  always_ff @(posedge clk) begin
    w_r31_q <= w_r31_mem[weight_addr_w];
    w_r32_q <= w_r32_mem[weight_addr_w];
    w_r63_q <= w_r63_mem[weight_addr_w];
  end

  // ---------------------------------------------------------------
  // Controller
  // ---------------------------------------------------------------
  logic tap_valid, tap_last, tap_clear;
  logic [IFMAP_BIN_WIDTH-1:0] pe_ifmap_bin;
  logic [N-1:0] pe_w1, pe_w2;
  logic [N:0]   pe_w3;
  logic out_valid;
  logic [$clog2(COUT)-1:0] out_cout;
  logic [$clog2(OH)-1:0]   out_oh;
  logic [$clog2(OW)-1:0]   out_ow;
  logic ifmap_ren_ctrl, weight_ren_ctrl;

  rns_pe_controller #(
      .N(N), .H(H), .W(W), .CIN(CIN), .COUT(COUT), .KH(KH), .KW(KW),
      .PAD(PAD), .STRIDE(STRIDE), .IFMAP_BIN_WIDTH(IFMAP_BIN_WIDTH)
  ) u_ctrl (
      .clk(clk), .rst_n(rst_n),
      .run(run), .layer_done(layer_done),
      .ifmap_ren(ifmap_ren_ctrl), .ifmap_addr(ifmap_addr_w), .ifmap_rdata(ifmap_rdata),
      .weight_ren(weight_ren_ctrl), .weight_addr(weight_addr_w),
      .weight_rdata_r31(w_r31_q), .weight_rdata_r32(w_r32_q), .weight_rdata_r63(w_r63_q),
      .tap_valid(tap_valid), .tap_last(tap_last), .tap_clear(tap_clear),
      .pe_ifmap_bin(pe_ifmap_bin), .pe_w1(pe_w1), .pe_w2(pe_w2), .pe_w3(pe_w3),
      .out_valid(out_valid), .out_cout(out_cout), .out_oh(out_oh), .out_ow(out_ow)
  );

  assign ifmap_ren_w = ifmap_ren_ctrl;

  // ---------------------------------------------------------------
  // PE
  // ---------------------------------------------------------------
  logic acc_valid;
  logic [N-1:0] ps_acc1, ps_acc2;
  logic [N:0]   ps_acc3;

  rns_pe #(
      .N(N), .MUL_EXT_BITS(MUL_EXT_BITS), .IFMAP_BIN_WIDTH(IFMAP_BIN_WIDTH)
  ) u_pe (
      .clk(clk), .rst_n(rst_n),
      .tap_valid(tap_valid), .tap_last(tap_last), .tap_clear(tap_clear),
      .ifmap_bin(pe_ifmap_bin), .w1(pe_w1), .w2(pe_w2), .w3(pe_w3),
      .acc_valid(acc_valid), .ps_acc1(ps_acc1), .ps_acc2(ps_acc2), .ps_acc3(ps_acc3)
  );

  // ---------------------------------------------------------------
  // Output RAM: raw partial sum per (cout,oh,ow), 3 residues packed per word
  // ---------------------------------------------------------------
  logic [N-1:0] out_r31 [OUT_DEPTH];
  logic [N-1:0] out_r32 [OUT_DEPTH];
  logic [N:0]   out_r63 [OUT_DEPTH];

  wire [$clog2(OUT_DEPTH)-1:0] out_addr = out_cout * OH * OW + out_oh * OW + out_ow;

  always_ff @(posedge clk) begin
    if (out_valid && acc_valid) begin
      out_r31[out_addr] <= ps_acc1;
      out_r32[out_addr] <= ps_acc2;
      out_r63[out_addr] <= ps_acc3;
    end
  end
  
  always_ff @(posedge clk) begin
    if (layer_done) begin
      $writememh("conv1_out_r31.mem", out_r31);
      $writememh("conv1_out_r32.mem", out_r32);
      $writememh("conv1_out_r63.mem", out_r63);
    end
  end

endmodule
