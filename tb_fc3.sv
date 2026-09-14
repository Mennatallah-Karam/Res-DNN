`timescale 1ns/1ps
`define DATA_PATH "D:/NU/RA/full_ResDNN"
module tb_fc3;
  tb_rns_layer #(
      .LAYER_NAME("fc3"),
      // Final classifier layer: 4096 -> 10, NO ReLU (Table 7.1 lists no
      // activation after FC3 -- these are raw logits and must stay signed).
      .C_IN(4096), .KERNEL(1), .NUM_CHANNELS(10), .H_OUT(1), .W_OUT(1), .POOL_KERNEL(1),
      .APPLY_RELU(0), .IFMAP_IS_RNS(1), .DO_POOL(0),
      .IFMAP_H_IN(1), .IFMAP_W_IN(1),
      // FC2 has no pooling -- its final activation is its RELU output.
      .IFMAP_R31_FILE({`DATA_PATH, "/hw_out/fc2_relu_r31.mem"}),
      .IFMAP_R32_FILE({`DATA_PATH, "/hw_out/fc2_relu_r32.mem"}),
      .IFMAP_R63_FILE({`DATA_PATH, "/hw_out/fc2_relu_r63.mem"}),
      .W1_FILE({`DATA_PATH, "/rns_params_out/fc3_weight_r31.mem"}),
      .W2_FILE({`DATA_PATH, "/rns_params_out/fc3_weight_r32.mem"}),
      .W3_FILE({`DATA_PATH, "/rns_params_out/fc3_weight_r63.mem"}),
      .B1_FILE({`DATA_PATH, "/rns_params_out/fc3_bias_r31.mem"}),
      .B2_FILE({`DATA_PATH, "/rns_params_out/fc3_bias_r32.mem"}),
      .B3_FILE({`DATA_PATH, "/rns_params_out/fc3_bias_r63.mem"}),
      .OUT_DIR({`DATA_PATH, "/hw_out/"})
  ) u_tb ();
endmodule