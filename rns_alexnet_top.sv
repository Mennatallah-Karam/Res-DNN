module rns_alexnet_top #(
    parameter string DATA_PATH  = "D:/NU/RA/full_ResDNN",
    parameter int    NUM_LAYERS = 8,
    parameter string IFMAP_FILE0 = {DATA_PATH, "/ifmap_bns.mem"}
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    output logic done
);

  typedef struct packed {
    int c_in;
    int kernel;
    int num_channels;
    int h_out;
    int w_out;
    int pool_kernel;   // 1 = no pooling
    int ifmap_h_in;    // this layer's ifmap spatial height. 0 for conv1 (BNS, unused).
    int ifmap_w_in;    // this layer's ifmap spatial width.  0 for conv1 (BNS, unused).
    bit apply_relu;    // 0 = raw logits (final classifier layer only)
    bit ifmap_is_rns;  // 0 = BNS raw (conv1 only), 1 = RNS residues
  } layer_cfg_t;

  localparam layer_cfg_t LAYERS [0:NUM_LAYERS-1] = '{
      '{c_in:3,    kernel:3, num_channels:64,   h_out:32, w_out:32, pool_kernel:2, ifmap_h_in:0,  ifmap_w_in:0,  apply_relu:1'b1, ifmap_is_rns:1'b0},  // conv1
      '{c_in:64,   kernel:3, num_channels:192,  h_out:16, w_out:16, pool_kernel:2, ifmap_h_in:16, ifmap_w_in:16, apply_relu:1'b1, ifmap_is_rns:1'b1},  // conv2 (from conv1 pool)
      '{c_in:192,  kernel:3, num_channels:384,  h_out:8,  w_out:8,  pool_kernel:1, ifmap_h_in:8,  ifmap_w_in:8,  apply_relu:1'b1, ifmap_is_rns:1'b1},  // conv3 (from conv2 pool, no pool)
      '{c_in:384,  kernel:3, num_channels:256,  h_out:8,  w_out:8,  pool_kernel:1, ifmap_h_in:8,  ifmap_w_in:8,  apply_relu:1'b1, ifmap_is_rns:1'b1},  // conv4 (from conv3 relu, no pool)
      '{c_in:256,  kernel:3, num_channels:256,  h_out:8,  w_out:8,  pool_kernel:2, ifmap_h_in:8,  ifmap_w_in:8,  apply_relu:1'b1, ifmap_is_rns:1'b1},  // conv5 (from conv4 relu)
      '{c_in:4096, kernel:1, num_channels:4096, h_out:1,  w_out:1,  pool_kernel:1, ifmap_h_in:1,  ifmap_w_in:1,  apply_relu:1'b1, ifmap_is_rns:1'b1},  // fc1 (flattened conv5 pool: 256*4*4)
      '{c_in:4096, kernel:1, num_channels:4096, h_out:1,  w_out:1,  pool_kernel:1, ifmap_h_in:1,  ifmap_w_in:1,  apply_relu:1'b1, ifmap_is_rns:1'b1},  // fc2 (from fc1 relu)
      '{c_in:4096, kernel:1, num_channels:10,   h_out:1,  w_out:1,  pool_kernel:1, ifmap_h_in:1,  ifmap_w_in:1,  apply_relu:1'b0, ifmap_is_rns:1'b1}   // fc3 (from fc2 relu, raw logits, no ReLU)
  };

  localparam string LAYER_NAME [0:NUM_LAYERS-1] = '{
      "conv1", "conv2", "conv3", "conv4", "conv5", "fc1", "fc2", "fc3"
  };

  logic [NUM_LAYERS-1:0] start_vec;
  logic [NUM_LAYERS-1:0] done_vec;

  genvar i;
  generate
    for (i = 0; i < NUM_LAYERS; i = i + 1) begin : g_layer
      if (i == 0) begin : g_inst
        logic [4:0] zero_r31 [0:0];
        logic [4:0] zero_r32 [0:0];
        logic [5:0] zero_r63 [0:0];
        assign zero_r31[0] = '0;
        assign zero_r32[0] = '0;
        assign zero_r63[0] = '0;

        rns_pe_top_chained #(
            .C_IN(LAYERS[i].c_in), .KERNEL(LAYERS[i].kernel), .NUM_CHANNELS(LAYERS[i].num_channels),
            .H_OUT(LAYERS[i].h_out), .W_OUT(LAYERS[i].w_out), .POOL_KERNEL(LAYERS[i].pool_kernel),
            .APPLY_RELU(LAYERS[i].apply_relu), .IFMAP_IS_RNS(LAYERS[i].ifmap_is_rns),
            .LIVE_IFMAP(1'b0),
            .IFMAP_H_IN(0), .IFMAP_W_IN(0),
            .IFMAP_FILE(IFMAP_FILE0),
            .W1_FILE({DATA_PATH, "/rns_params_out/", LAYER_NAME[i], "_weight_r31.mem"}),
            .W2_FILE({DATA_PATH, "/rns_params_out/", LAYER_NAME[i], "_weight_r32.mem"}),
            .W3_FILE({DATA_PATH, "/rns_params_out/", LAYER_NAME[i], "_weight_r63.mem"}),
            .B1_FILE({DATA_PATH, "/rns_params_out/", LAYER_NAME[i], "_bias_r31.mem"}),
            .B2_FILE({DATA_PATH, "/rns_params_out/", LAYER_NAME[i], "_bias_r32.mem"}),
            .B3_FILE({DATA_PATH, "/rns_params_out/", LAYER_NAME[i], "_bias_r63.mem"})
        ) u_layer (
            .clk(clk), .rst_n(rst_n), .start(start_vec[i]),
            .prev_r31(zero_r31), .prev_r32(zero_r32), .prev_r63(zero_r63),
            .out_r31(), .out_r32(), .out_r63(),
            .done(done_vec[i])
        );

      end else begin : g_inst
        rns_pe_top_chained #(
            .C_IN(LAYERS[i].c_in), .KERNEL(LAYERS[i].kernel), .NUM_CHANNELS(LAYERS[i].num_channels),
            .H_OUT(LAYERS[i].h_out), .W_OUT(LAYERS[i].w_out), .POOL_KERNEL(LAYERS[i].pool_kernel),
            .APPLY_RELU(LAYERS[i].apply_relu), .IFMAP_IS_RNS(LAYERS[i].ifmap_is_rns),
            .LIVE_IFMAP(1'b1),
            .IFMAP_H_IN(LAYERS[i].ifmap_h_in), .IFMAP_W_IN(LAYERS[i].ifmap_w_in),
            .IFMAP_FILE("unused.mem"),
            .W1_FILE({DATA_PATH, "/rns_params_out/", LAYER_NAME[i], "_weight_r31.mem"}),
            .W2_FILE({DATA_PATH, "/rns_params_out/", LAYER_NAME[i], "_weight_r32.mem"}),
            .W3_FILE({DATA_PATH, "/rns_params_out/", LAYER_NAME[i], "_weight_r63.mem"}),
            .B1_FILE({DATA_PATH, "/rns_params_out/", LAYER_NAME[i], "_bias_r31.mem"}),
            .B2_FILE({DATA_PATH, "/rns_params_out/", LAYER_NAME[i], "_bias_r32.mem"}),
            .B3_FILE({DATA_PATH, "/rns_params_out/", LAYER_NAME[i], "_bias_r63.mem"})
        ) u_layer (
            .clk(clk), .rst_n(rst_n), .start(start_vec[i]),
            .prev_r31(g_layer[i-1].g_inst.u_layer.out_r31),
            .prev_r32(g_layer[i-1].g_inst.u_layer.out_r32),
            .prev_r63(g_layer[i-1].g_inst.u_layer.out_r63),
            .out_r31(), .out_r32(), .out_r63(),
            .done(done_vec[i])
        );
      end
    end
  endgenerate

  // ---- sequencer: start layer 0, wait for its done, start layer 1, ... ----
  typedef enum logic [1:0] {S_IDLE, S_WAIT, S_SETTLE, S_DONE} seq_state_t;
  seq_state_t seq_state;
  logic [$clog2(NUM_LAYERS+1)-1:0] cur_layer;
  logic [1:0] settle_cnt;   // small margin cycle, mirrors your tb's extra @(posedge clk)s

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      seq_state  <= S_IDLE;
      cur_layer  <= '0;
      start_vec  <= '0;
      settle_cnt <= '0;
      done       <= 1'b0;
    end else begin
      start_vec <= '0;   // start pulses are single-cycle
      done      <= 1'b0;

      case (seq_state)
        S_IDLE: begin
          if (start) begin
            cur_layer    <= '0;
            start_vec[0] <= 1'b1;
            seq_state    <= S_WAIT;
          end
        end

        S_WAIT: begin
          if (done_vec[cur_layer]) begin
            settle_cnt <= '0;
            seq_state  <= S_SETTLE;
          end
        end

        S_SETTLE: begin
          if (settle_cnt == 2'd1) begin
            if (cur_layer == NUM_LAYERS - 1) begin
              seq_state <= S_DONE;
            end else begin
              cur_layer               <= cur_layer + 1'b1;
              start_vec[cur_layer + 1'b1] <= 1'b1;
              seq_state                <= S_WAIT;
            end
          end else begin
            settle_cnt <= settle_cnt + 1'b1;
          end
        end

        S_DONE: begin
          done      <= 1'b1;
          seq_state <= S_IDLE;
        end

        default: seq_state <= S_IDLE;
      endcase
    end
  end

endmodule : rns_alexnet_top