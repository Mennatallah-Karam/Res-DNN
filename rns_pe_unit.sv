module rns_pe_unit #(
    parameter int INPUT_WIDTH  = 16,   // BNS ifmap width (signed) -- only used when IFMAP_IS_RNS=0
    parameter int K_MUL        = 3,    // multiply-domain extension / scale-down amount
    parameter int K_ADD        = 6,    // add-domain (bias) extension / scale-down amount
    parameter bit IFMAP_IS_RNS = 0     // 0: ifmap_bin is raw BNS, forward-converted here (conv1).
                                      // 1: ifmap_r31/32/63 are already RNS residues (conv2+)
) (
    input  logic                          clk,
    input  logic                          rst_n,

    input  logic signed [INPUT_WIDTH-1:0] ifmap_bin,   // used when IFMAP_IS_RNS=0
    input  logic [4:0]                    ifmap_r31,   // used when IFMAP_IS_RNS=1
    input  logic [4:0]                    ifmap_r32,   // used when IFMAP_IS_RNS=1
    input  logic [5:0]                    ifmap_r63,   // used when IFMAP_IS_RNS=1

    input  logic [4:0]                    w1,          // weight residue mod31
    input  logic [4:0]                    w2,          // weight residue mod32
    input  logic [5:0]                    w3,          // weight residue mod63
    input  logic [4:0]                    bias1,       // bias residue mod31 (held stable through last_mac)
    input  logic [4:0]                    bias2,       // bias residue mod32
    input  logic [5:0]                    bias3,       // bias residue mod63

    // ---- control ----
    input  logic                          mac_valid,   // pulse: consume this tap
    input  logic                          last_mac,    // this tap is the last one for the current output
    input  logic                          reset_accum, // assert together with the FIRST mac_valid of a new output

    // ---- output ----
    output logic [4:0]                    out1,
    output logic [4:0]                    out2,
    output logic [5:0]                    out3,
    output logic                          out_valid,
    output logic                          busy
);

  // ------------------------------------------------------------------
  // Stage 1: ifmap source select.
  //   IFMAP_IS_RNS=0 (conv1): BNS -> RNS forward conversion, same as before.
  //   IFMAP_IS_RNS=1 (conv2+): ifmap already arrived as residues from the
  //   previous layer's output memory -- wire straight through, no converter.
  // ------------------------------------------------------------------
  logic [4:0] i1_raw, i2_raw;
  logic [5:0] i3_raw;

  generate
    if (IFMAP_IS_RNS) begin : g_rns_ifmap
      assign i1_raw = ifmap_r31;
      assign i2_raw = ifmap_r32;
      assign i3_raw = ifmap_r63;
    end else begin : g_bns_ifmap
      rns_forward_converter #(.INPUT_WIDTH(INPUT_WIDTH)) u_fwd_i (
          .x_bin(ifmap_bin),
          .x1   (i1_raw),
          .x2   (i2_raw),
          .x3   (i3_raw)
      );
    end
  endgenerate

  logic       valid_s1, valid_s2, valid_s3;
  logic       last_s1,  last_s2,  last_s3;
  logic       reset_s1, reset_s2, reset_s3;
  logic [4:0] w1_s1, w1_s2;
  logic [4:0] w2_s1, w2_s2;
  logic [5:0] w3_s1, w3_s2;
  logic [4:0] i1_s1, i1_s2;
  logic [4:0] i2_s1, i2_s2;
  logic [5:0] i3_s1, i3_s2;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_s1 <= 1'b0;
      last_s1  <= 1'b0;
      reset_s1 <= 1'b0;
    end else begin
      valid_s1 <= mac_valid;
      last_s1  <= last_mac;
      reset_s1 <= reset_accum;
      w1_s1    <= w1;
      w2_s1    <= w2;
      w3_s1    <= w3;
      i1_s1    <= i1_raw;
      i2_s1    <= i2_raw;
      i3_s1    <= i3_raw;
    end
  end

  // ------------------------------------------------------------------
  // Stage 2: base extension (weight and ifmap power-of-two channel)
  // ------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_s2 <= 1'b0;
      last_s2  <= 1'b0;
      reset_s2 <= 1'b0;
    end else begin
      valid_s2 <= valid_s1;
      last_s2  <= last_s1;
      reset_s2 <= reset_s1;
      w1_s2    <= w1_s1;
      w2_s2    <= w2_s1;
      w3_s2    <= w3_s1;
      i1_s2    <= i1_s1;
      i2_s2    <= i2_s1;
      i3_s2    <= i3_s1;
    end
  end

  logic [4+K_MUL:0] w2_ext_s2, i2_ext_s2;

  rns_base_extension #(.E(K_MUL)) u_ext_w (
      .x1(w1_s2), .x2(w2_s2), .x3(w3_s2), .x2_ext(w2_ext_s2)
  );
  rns_base_extension #(.E(K_MUL)) u_ext_i (
      .x1(i1_s2), .x2(i2_s2), .x3(i3_s2), .x2_ext(i2_ext_s2)
  );

  logic [4:0]       w1_s3;
  logic [5:0]       w3_s3;
  logic [4:0]       i1_s3;
  logic [5:0]       i3_s3;
  logic [4+K_MUL:0] w2_ext_s3, i2_ext_s3;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_s3 <= 1'b0;
      last_s3  <= 1'b0;
      reset_s3 <= 1'b0;
    end else begin
      valid_s3  <= valid_s2;
      last_s3   <= last_s2;
      reset_s3  <= reset_s2;
      w1_s3     <= w1_s2;
      w3_s3     <= w3_s2;
      i1_s3     <= i1_s2;
      i3_s3     <= i3_s2;
      w2_ext_s3 <= w2_ext_s2;
      i2_ext_s3 <= i2_ext_s2;
    end
  end

  // ------------------------------------------------------------------
  // Stage 3: channel multiply (combinational, same cycle).
  // ------------------------------------------------------------------
  logic [4:0]       p1_s3;
  logic [4+K_MUL:0] p2_ext_s3;
  logic [5:0]       p3_s3;

  rns_channel_multiplier #(.W(5),       .MERSENNE(1)) u_mul1 (.in1(w1_s3), .in2(i1_s3), .prod(p1_s3));
  rns_channel_multiplier #(.W(5+K_MUL), .MERSENNE(0)) u_mul2 (.in1(w2_ext_s3), .in2(i2_ext_s3), .prod(p2_ext_s3));
  rns_channel_multiplier #(.W(6),       .MERSENNE(1)) u_mul3 (.in1(w3_s3), .in2(i3_s3), .prod(p3_s3));

  // ------------------------------------------------------------------
  // Raw (unshifted) accumulation, per residue channel, in the EXTENDED
  // multiply domain. reset_s3 initializes the accumulator with the
  // FIRST tap's raw product instead of adding into a stale register.
  // ------------------------------------------------------------------
  logic [4:0]       acc31_q;
  logic [4+K_MUL:0] acc32ext_q;
  logic [5:0]       acc63_q;

  logic [5:0] acc31_sum;
  logic [6:0] acc63_sum;

  assign acc31_sum = {1'b0, acc31_q} + {1'b0, p1_s3};
  assign acc63_sum = {1'b0, acc63_q} + {1'b0, p3_s3};

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc31_q    <= '0;
      acc32ext_q <= '0;
      acc63_q    <= '0;
    end else if (valid_s3) begin
      if (reset_s3) begin
        acc31_q    <= p1_s3;
        acc32ext_q <= p2_ext_s3;         // mod 2^(5+K_MUL): plain load, nothing special needed
        acc63_q    <= p3_s3;
      end else begin
        acc31_q    <= (acc31_sum >= 6'd31) ? (acc31_sum[4:0] - 5'd31) : acc31_sum[4:0];
        acc32ext_q <= acc32ext_q + p2_ext_s3;   // (5+K_MUL)-bit wraparound == mod 2^(5+K_MUL)
        acc63_q    <= (acc63_sum >= 7'd63) ? (acc63_sum[5:0] - 6'd63) : acc63_sum[5:0];
      end
    end
  end

  localparam int BIAS_FIFO_DEPTH = 4;

  logic [4:0] bias1_fifo [0:BIAS_FIFO_DEPTH-1];
  logic [4:0] bias2_fifo [0:BIAS_FIFO_DEPTH-1];
  logic [5:0] bias3_fifo [0:BIAS_FIFO_DEPTH-1];
  logic [$clog2(BIAS_FIFO_DEPTH)-1:0] bias_wr_ptr, bias_rd_ptr;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bias_wr_ptr <= '0;
    end else if (mac_valid && reset_accum) begin
      bias1_fifo[bias_wr_ptr] <= bias1;
      bias2_fifo[bias_wr_ptr] <= bias2;
      bias3_fifo[bias_wr_ptr] <= bias3;
      bias_wr_ptr <= bias_wr_ptr + 1'b1;
    end
  end

  // ------------------------------------------------------------------
  // Single scale-down by K_MUL, once per output (after the last tap).
  // ------------------------------------------------------------------
  logic mul_done, mul_done_d;
  logic [4:0] bias1_q;
  logic [4:0] bias2_q;
  logic [5:0] bias3_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bias_rd_ptr <= '0;
      mul_done    <= 1'b0;
      bias1_q <= '0; bias2_q <= '0; bias3_q <= '0;
    end else begin
      mul_done <= valid_s3 && last_s3;
      if (valid_s3 && last_s3) begin
        bias1_q     <= bias1_fifo[bias_rd_ptr];
        bias2_q     <= bias2_fifo[bias_rd_ptr];
        bias3_q     <= bias3_fifo[bias_rd_ptr];
        bias_rd_ptr <= bias_rd_ptr + 1'b1;
      end
    end
  end

  logic [4:0] mul_s1;
  logic [4:0] mul_s2;
  logic [5:0] mul_s3;

  rns_scaling_unit #(.E(K_MUL)) u_scale_mul (
      .x1(acc31_q), .x2(acc32ext_q), .x3(acc63_q),
      .xS1(mul_s1), .xS2(mul_s2), .xS3(mul_s3)
  );

  // ------------------------------------------------------------------
  // Bias merge, BEFORE the add-domain scale-down.
  // ------------------------------------------------------------------
  logic [4+K_ADD:0] psum2_ext_add;

  rns_base_extension #(.E(K_ADD)) u_ext_bias (
      .x1(mul_s1), .x2(mul_s2), .x3(mul_s3), .x2_ext(psum2_ext_add)
  );

  localparam int POW2_KADD_MOD31 = (1 << K_ADD) % 31;
  localparam int POW2_KADD_MOD63 = (1 << K_ADD) % 63;

  logic [4:0]       bias1_shifted;
  logic [5:0]       bias3_shifted;
  logic [4+K_ADD:0] bias2_ext_shifted;

  rns_channel_multiplier #(.W(5), .MERSENNE(1)) u_bias1_shift (
      .in1(bias1_q), .in2(5'(POW2_KADD_MOD31)), .prod(bias1_shifted)
  );
  rns_channel_multiplier #(.W(6), .MERSENNE(1)) u_bias3_shift (
      .in1(bias3_q), .in2(6'(POW2_KADD_MOD63)), .prod(bias3_shifted)
  );
  assign bias2_ext_shifted = {bias2_q, {K_ADD{1'b0}}};

  logic [4:0]       sum1;
  logic [4+K_ADD:0] sum2_ext;
  logic [5:0]       sum3;

  logic [5:0] sum1_calc;
  logic [6:0] sum3_calc;

  assign sum1_calc = {1'b0, mul_s1} + {1'b0, bias1_shifted};
  assign sum3_calc = {1'b0, mul_s3} + {1'b0, bias3_shifted};

  assign sum1     = (sum1_calc >= 6'd31) ? (sum1_calc[4:0] - 5'd31) : sum1_calc[4:0];
  assign sum3     = (sum3_calc >= 7'd63) ? (sum3_calc[5:0] - 6'd63) : sum3_calc[5:0];
  assign sum2_ext = psum2_ext_add + bias2_ext_shifted;

  logic [4:0]        sum1_q;
  logic [4+K_ADD:0]  sum2ext_q;
  logic [5:0]        sum3_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mul_done_d <= 1'b0;
      sum1_q <= '0; sum2ext_q <= '0; sum3_q <= '0;
    end else begin
      mul_done_d <= mul_done;
      if (mul_done) begin
        sum1_q    <= sum1;
        sum2ext_q <= sum2_ext;
        sum3_q    <= sum3;
      end
    end
  end

  // ------------------------------------------------------------------
  // Final scale-down by K_ADD.
  // ------------------------------------------------------------------
  logic [4:0] add_ps1;
  logic [4:0] add_ps2;
  logic [5:0] add_ps3;

  rns_scaling_unit #(.E(K_ADD)) u_scale_add (
      .x1(sum1_q), .x2(sum2ext_q), .x3(sum3_q),
      .xS1(add_ps1), .xS2(add_ps2), .xS3(add_ps3)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out1 <= '0; out2 <= '0; out3 <= '0; out_valid <= 1'b0;
    end else begin
      out_valid <= mul_done_d;
      if (mul_done_d) begin
        out1 <= add_ps1;
        out2 <= add_ps2;
        out3 <= add_ps3;
      end
    end
  end

  assign busy = valid_s1 | valid_s2 | valid_s3 | mul_done | mul_done_d;

endmodule
