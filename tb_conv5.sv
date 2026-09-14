`timescale 1ns/1ps
`define DATA_PATH "D:/NU/RA/full_ResDNN"
module tb_conv5;
  tb_rns_layer #(
      .LAYER_NAME("conv5"),
      .C_IN(256), .KERNEL(3), .NUM_CHANNELS(256), .H_OUT(8), .W_OUT(8), .POOL_KERNEL(2),
      .IFMAP_IS_RNS(1), .DO_POOL(1),
      .IFMAP_H_IN(8), .IFMAP_W_IN(8),   // conv4's H_OUT/W_OUT (no pooling)
      .IFMAP_R31_FILE({`DATA_PATH, "/hw_out/conv4_relu_r31.mem"}),
      .IFMAP_R32_FILE({`DATA_PATH, "/hw_out/conv4_relu_r32.mem"}),
      .IFMAP_R63_FILE({`DATA_PATH, "/hw_out/conv4_relu_r63.mem"}),
      .W1_FILE({`DATA_PATH, "/rns_params_out/conv5_weight_r31.mem"}),
      .W2_FILE({`DATA_PATH, "/rns_params_out/conv5_weight_r32.mem"}),
      .W3_FILE({`DATA_PATH, "/rns_params_out/conv5_weight_r63.mem"}),
      .B1_FILE({`DATA_PATH, "/rns_params_out/conv5_bias_r31.mem"}),
      .B2_FILE({`DATA_PATH, "/rns_params_out/conv5_bias_r32.mem"}),
      .B3_FILE({`DATA_PATH, "/rns_params_out/conv5_bias_r63.mem"}),
      .OUT_DIR({`DATA_PATH, "/hw_out/"})
  ) u_tb ();
endmodule