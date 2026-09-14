module rns_pe_top_chained #(
    parameter int INPUT_WIDTH   = 16,
    parameter int K_MUL         = 3,
    parameter int K_ADD         = 6,

    parameter int C_IN          = 3,
    parameter int KERNEL        = 3,
    parameter int NUM_CHANNELS  = 64,
    parameter int H_OUT         = 32,
    parameter int W_OUT         = 32,
    parameter int POOL_KERNEL   = 2,
    parameter bit APPLY_RELU    = 1,

    parameter bit IFMAP_IS_RNS  = 0,
    parameter bit LIVE_IFMAP    = 0,   // only meaningful when IFMAP_IS_RNS=1
    parameter int IFMAP_H_IN    = 0,
    parameter int IFMAP_W_IN    = 0,

    parameter string IFMAP_FILE      = "ifmap_bns.mem",
    parameter string IFMAP_R31_FILE  = "ifmap_r31.mem",
    parameter string IFMAP_R32_FILE  = "ifmap_r32.mem",
    parameter string IFMAP_R63_FILE  = "ifmap_r63.mem",

    parameter string W1_FILE    = "weight_r31.mem",
    parameter string W2_FILE    = "weight_r32.mem",
    parameter string W3_FILE    = "weight_r63.mem",
    parameter string B1_FILE    = "bias_r31.mem",
    parameter string B2_FILE    = "bias_r32.mem",
    parameter string B3_FILE    = "bias_r63.mem",

    // ---- derived (guarded against size-1 dims, same convention as rns_pe_top) ----
    localparam int NUM_TAPS       = C_IN * KERNEL * KERNEL,
    localparam int H_PAD          = H_OUT + KERNEL - 1,
    localparam int W_PAD          = W_OUT + KERNEL - 1,
    localparam int H_POOL         = H_OUT / POOL_KERNEL,
    localparam int W_POOL         = W_OUT / POOL_KERNEL,
    localparam int NUM_WINDOWS    = H_POOL * W_POOL,
    localparam int POOL_SIZE      = POOL_KERNEL * POOL_KERNEL,

    localparam int IFMAP_DEPTH    = C_IN * H_PAD * W_PAD,
    localparam int WEIGHT_DEPTH   = NUM_CHANNELS * NUM_TAPS,
    localparam int BIAS_DEPTH     = NUM_CHANNELS,
    localparam int OUT_DEPTH      = (NUM_CHANNELS * NUM_WINDOWS <= 1) ? 1 : NUM_CHANNELS * NUM_WINDOWS,
    localparam int PRE_POOL_DEPTH = NUM_CHANNELS * H_OUT * W_OUT,
    localparam int PREV_DEPTH     = (C_IN * IFMAP_H_IN * IFMAP_W_IN <= 1) ? 1 : C_IN * IFMAP_H_IN * IFMAP_W_IN,

    localparam int WEIGHT_ADDR_W  = (WEIGHT_DEPTH   <= 1) ? 1 : $clog2(WEIGHT_DEPTH),
    localparam int IFMAP_ADDR_W   = (IFMAP_DEPTH    <= 1) ? 1 : $clog2(IFMAP_DEPTH),
    localparam int BIAS_ADDR_W    = (BIAS_DEPTH     <= 1) ? 1 : $clog2(BIAS_DEPTH),
    localparam int PIX_ADDR_W     = (PRE_POOL_DEPTH <= 1) ? 1 : $clog2(PRE_POOL_DEPTH),
    localparam int CW             = (C_IN           <= 1) ? 1 : $clog2(C_IN),
    localparam int ROW_W          = (H_PAD          <= 1) ? 1 : $clog2(H_PAD),
    localparam int COL_W          = (W_PAD          <= 1) ? 1 : $clog2(W_PAD)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,

    // previous layer's live activation store (only read when LIVE_IFMAP=1)
    input  logic [4:0] prev_r31 [0:PREV_DEPTH-1],
    input  logic [4:0] prev_r32 [0:PREV_DEPTH-1],
    input  logic [5:0] prev_r63 [0:PREV_DEPTH-1],

    // this layer's pooled (or pass-through, if POOL_KERNEL=1) activations
    output logic [4:0] out_r31 [0:OUT_DEPTH-1],
    output logic [4:0] out_r32 [0:OUT_DEPTH-1],
    output logic [5:0] out_r63 [0:OUT_DEPTH-1],

    output logic done   // asserted once act_wr_ptr==OUT_DEPTH (see module header)
);

  logic [PIX_ADDR_W-1:0] pixel_addr;
  logic                          mem_rd_en;
  logic [IFMAP_ADDR_W-1:0]       ifmap_rd_addr;
  logic [WEIGHT_ADDR_W-1:0]      weight_rd_addr;
  logic [BIAS_ADDR_W-1:0]        bias_rd_addr;
  logic                          mac_valid, last_mac, reset_accum, ctrl_busy, ctrl_done;
  logic                          pool_first, pool_last;
  logic [CW-1:0]                 ifmap_cin;
  logic [ROW_W-1:0]              ifmap_row;
  logic [COL_W-1:0]              ifmap_col;

  rns_pe_controller #(
      .C_IN(C_IN), .KERNEL(KERNEL), .NUM_CHANNELS(NUM_CHANNELS),
      .H_OUT(H_OUT), .W_OUT(W_OUT), .POOL_KERNEL(POOL_KERNEL)
  ) u_ctrl (
      .clk(clk), .rst_n(rst_n), .start(start),
      .mem_rd_en(mem_rd_en), .ifmap_rd_addr(ifmap_rd_addr),
      .weight_rd_addr(weight_rd_addr), .bias_rd_addr(bias_rd_addr),
      .mac_valid(mac_valid), .last_mac(last_mac), .reset_accum(reset_accum),
      .pool_first(pool_first), .pool_last(pool_last), .pixel_addr(pixel_addr),
      .ifmap_cin(ifmap_cin), .ifmap_row(ifmap_row), .ifmap_col(ifmap_col),
      .busy(ctrl_busy), .done(ctrl_done)   // NOTE: ctrl_done intentionally unused for `done` below
  );

  logic signed [INPUT_WIDTH-1:0] ifmap_bin;
  logic [4:0] ifmap_r31_w;
  logic [4:0] ifmap_r32_w;
  logic [5:0] ifmap_r63_w;

  generate
    if (IFMAP_IS_RNS) begin : g_rns_ifmap
      assign ifmap_bin = '0;
      if (LIVE_IFMAP) begin : g_live
        rns_ifmap_live_padded #(
            .C_IN(C_IN), .H_IN(IFMAP_H_IN), .W_IN(IFMAP_W_IN), .PAD(KERNEL / 2)
        ) u_ifmap_mem (
            .clk(clk), .rst_n(rst_n),
            .cin(ifmap_cin), .row(ifmap_row), .col(ifmap_col),
            .src_r31(prev_r31), .src_r32(prev_r32), .src_r63(prev_r63),
            .r31(ifmap_r31_w), .r32(ifmap_r32_w), .r63(ifmap_r63_w)
        );
      end else begin : g_file
        rns_ifmap_rns_mem_padded #(
            .C_IN(C_IN), .H_IN(IFMAP_H_IN), .W_IN(IFMAP_W_IN), .PAD(KERNEL / 2),
            .R31_FILE(IFMAP_R31_FILE), .R32_FILE(IFMAP_R32_FILE), .R63_FILE(IFMAP_R63_FILE)
        ) u_ifmap_mem (
            .cin(ifmap_cin), .row(ifmap_row), .col(ifmap_col),
            .r31(ifmap_r31_w), .r32(ifmap_r32_w), .r63(ifmap_r63_w)
        );
      end
    end else begin : g_bns_ifmap
      assign ifmap_r31_w = '0;
      assign ifmap_r32_w = '0;
      assign ifmap_r63_w = '0;
      rns_ifmap_mem #(
          .DATA_WIDTH(INPUT_WIDTH), .DEPTH(IFMAP_DEPTH), .MEM_FILE(IFMAP_FILE)
      ) u_ifmap_mem (
          .addr(ifmap_rd_addr), .data(ifmap_bin)
      );
    end
  endgenerate

  logic [4:0] w1; logic [4:0] w2; logic [5:0] w3;
  rns_weight_mem #(
      .DEPTH(WEIGHT_DEPTH), .W1_FILE(W1_FILE), .W2_FILE(W2_FILE), .W3_FILE(W3_FILE)
  ) u_weight_mem (.addr(weight_rd_addr), .w1(w1), .w2(w2), .w3(w3));

  logic [4:0] bias1; logic [4:0] bias2; logic [5:0] bias3;
  rns_bias_mem #(
      .DEPTH(BIAS_DEPTH), .B1_FILE(B1_FILE), .B2_FILE(B2_FILE), .B3_FILE(B3_FILE)
  ) u_bias_mem (.addr(bias_rd_addr), .bias1(bias1), .bias2(bias2), .bias3(bias3));

  // ---- control/weight/bias delay-match stage (see header comment) ----
  logic                    mac_valid_l, last_mac_l, reset_accum_l;
  logic                    pool_first_l, pool_last_l;
  logic [PIX_ADDR_W-1:0]   pixel_addr_l;
  logic [4:0]              w1_l, w2_l, bias1_l, bias2_l;
  logic [5:0]              w3_l, bias3_l;

  generate
    if (LIVE_IFMAP) begin : g_ctrl_delay
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          mac_valid_l   <= 1'b0;
          last_mac_l    <= 1'b0;
          reset_accum_l <= 1'b0;
          pool_first_l  <= 1'b0;
          pool_last_l   <= 1'b0;
          pixel_addr_l  <= '0;
          w1_l <= '0; w2_l <= '0; w3_l <= '0;
          bias1_l <= '0; bias2_l <= '0; bias3_l <= '0;
        end else begin
          mac_valid_l   <= mac_valid;
          last_mac_l    <= last_mac;
          reset_accum_l <= reset_accum;
          pool_first_l  <= pool_first;
          pool_last_l   <= pool_last;
          pixel_addr_l  <= pixel_addr;
          w1_l <= w1; w2_l <= w2; w3_l <= w3;
          bias1_l <= bias1; bias2_l <= bias2; bias3_l <= bias3;
        end
      end
    end else begin : g_ctrl_passthrough
      assign mac_valid_l   = mac_valid;
      assign last_mac_l    = last_mac;
      assign reset_accum_l = reset_accum;
      assign pool_first_l  = pool_first;
      assign pool_last_l   = pool_last;
      assign pixel_addr_l  = pixel_addr;
      assign w1_l = w1; assign w2_l = w2; assign w3_l = w3;
      assign bias1_l = bias1; assign bias2_l = bias2; assign bias3_l = bias3;
    end
  endgenerate

  logic [4:0] out1; logic [4:0] out2; logic [5:0] out3; logic out_valid; logic layer_busy;
  logic [4:0] conv_out1; logic [4:0] conv_out2; logic [5:0] conv_out3; logic conv_out_valid;
  logic [PIX_ADDR_W-1:0] conv_out_addr, relu_out_addr;
  logic [4:0] relu_out1; logic [4:0] relu_out2; logic [5:0] relu_out3; logic relu_out_valid;

  rns_conv_relu_pool_layer #(
      .INPUT_WIDTH(INPUT_WIDTH), .K_MUL(K_MUL), .K_ADD(K_ADD),
      .N(5), .POOL_SIZE(POOL_SIZE), .CTRL_FIFO_DEPTH(4),
      .PIX_ADDR_W(PIX_ADDR_W), .IFMAP_IS_RNS(IFMAP_IS_RNS), .APPLY_RELU(APPLY_RELU)
  ) u_layer (
      .clk(clk), .rst_n(rst_n),
      .ifmap_bin(ifmap_bin),
      .ifmap_r31(ifmap_r31_w), .ifmap_r32(ifmap_r32_w), .ifmap_r63(ifmap_r63_w),
      .w1(w1_l), .w2(w2_l), .w3(w3_l),
      .bias1(bias1_l), .bias2(bias2_l), .bias3(bias3_l),
      .mac_valid(mac_valid_l), .last_mac(last_mac_l), .reset_accum(reset_accum_l),
      .pool_first(pool_first_l), .pool_last(pool_last_l), .pixel_addr(pixel_addr_l),
      .conv_out_mod31(conv_out1), .conv_out_mod32(conv_out2), .conv_out_mod63(conv_out3),
      .conv_out_valid(conv_out_valid), .conv_out_addr(conv_out_addr),
      .relu_dbg_mod31(relu_out1), .relu_dbg_mod32(relu_out2), .relu_dbg_mod63(relu_out3),
      .relu_dbg_valid(relu_out_valid), .relu_out_addr(relu_out_addr),
      .out_mod31(out1), .out_mod32(out2), .out_mod63(out3),
      .out_valid(out_valid), .busy(layer_busy)
  );

  // Pooled (or pass-through) activation store -- feeds the next layer live.
  logic [$clog2(OUT_DEPTH+1)-1:0] act_wr_ptr;
  rns_act_store #(.DEPTH(OUT_DEPTH)) u_act_store (
      .clk(clk), .rst_n(rst_n),
      .in1(out1), .in2(out2), .in3(out3), .in_valid(out_valid),
      .mem1(out_r31), .mem2(out_r32), .mem3(out_r63),
      .wr_ptr(act_wr_ptr)
  );

  // done := every pooled output actually landed in the array (see header).
  // Cleared on `start` so it can't be misread as stale-high by the sequencer.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      done <= 1'b0;
    end else if (start) begin
      done <= 1'b0;
    end else if (act_wr_ptr == OUT_DEPTH) begin
      done <= 1'b1;
    end
  end

endmodule : rns_pe_top_chained