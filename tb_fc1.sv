`timescale 1ns/1ps
`define DATA_PATH "D:/NU/RA/full_ResDNN"
module tb_fc1;
  tb_rns_layer #(
      .LAYER_NAME("fc1"),
      // FC layer = 1x1 conv, no pooling. C_IN = flattened conv5+pool3
      // output (256 channels * 4x4 spatial = 4096), NUM_CHANNELS = FC1's
      // own output width (4096, per Table 7.1).
      .C_IN(4096), .KERNEL(1), .NUM_CHANNELS(4096), .H_OUT(1), .W_OUT(1), .POOL_KERNEL(1),
      .APPLY_RELU(1), .IFMAP_IS_RNS(1), .DO_POOL(0),
      .IFMAP_H_IN(1), .IFMAP_W_IN(1),
      .IFMAP_R31_FILE({`DATA_PATH, "/hw_out/conv5_pool_r31.mem"}),
      .IFMAP_R32_FILE({`DATA_PATH, "/hw_out/conv5_pool_r32.mem"}),
      .IFMAP_R63_FILE({`DATA_PATH, "/hw_out/conv5_pool_r63.mem"}),
      .W1_FILE({`DATA_PATH, "/rns_params_out/fc1_weight_r31.mem"}),
      .W2_FILE({`DATA_PATH, "/rns_params_out/fc1_weight_r32.mem"}),
      .W3_FILE({`DATA_PATH, "/rns_params_out/fc1_weight_r63.mem"}),
      .B1_FILE({`DATA_PATH, "/rns_params_out/fc1_bias_r31.mem"}),
      .B2_FILE({`DATA_PATH, "/rns_params_out/fc1_bias_r32.mem"}),
      .B3_FILE({`DATA_PATH, "/rns_params_out/fc1_bias_r63.mem"}),
      .OUT_DIR({`DATA_PATH, "/hw_out/"})
  ) u_tb ();
endmodule