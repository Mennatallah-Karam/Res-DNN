`timescale 1ns/1ps
`define DATA_PATH "D:/NU/RA/full_ResDNN"
module tb_conv3;
  tb_rns_layer #(
      .LAYER_NAME("conv3"),
      .C_IN(192), .KERNEL(3), .NUM_CHANNELS(384), .H_OUT(8), .W_OUT(8), .POOL_KERNEL(1),
      .IFMAP_IS_RNS(1), .DO_POOL(0),
      .IFMAP_H_IN(8), .IFMAP_W_IN(8),   // conv2's H_POOL/W_POOL
      .IFMAP_R31_FILE({`DATA_PATH, "/hw_out/conv2_pool_r31.mem"}),
      .IFMAP_R32_FILE({`DATA_PATH, "/hw_out/conv2_pool_r32.mem"}),
      .IFMAP_R63_FILE({`DATA_PATH, "/hw_out/conv2_pool_r63.mem"}),
      .W1_FILE({`DATA_PATH, "/rns_params_out/conv3_weight_r31.mem"}),
      .W2_FILE({`DATA_PATH, "/rns_params_out/conv3_weight_r32.mem"}),
      .W3_FILE({`DATA_PATH, "/rns_params_out/conv3_weight_r63.mem"}),
      .B1_FILE({`DATA_PATH, "/rns_params_out/conv3_bias_r31.mem"}),
      .B2_FILE({`DATA_PATH, "/rns_params_out/conv3_bias_r32.mem"}),
      .B3_FILE({`DATA_PATH, "/rns_params_out/conv3_bias_r63.mem"}),
      .OUT_DIR({`DATA_PATH, "/hw_out/"})
  ) u_tb ();
endmodule