`timescale 1ns/1ps
`define DATA_PATH "D:/NU/RA/full_ResDNN"
module tb_conv1;
  tb_rns_layer #(
      .LAYER_NAME("conv1"),
      .C_IN(3), .KERNEL(3), .NUM_CHANNELS(64), .H_OUT(32), .W_OUT(32), .POOL_KERNEL(2),
      .IFMAP_IS_RNS(0), .DO_POOL(1),
      .IFMAP_FILE({`DATA_PATH, "/sw_trace/mem/ifmap_bns.mem"}),
      .W1_FILE({`DATA_PATH, "/rns_params_out/conv1_weight_r31.mem"}),
      .W2_FILE({`DATA_PATH, "/rns_params_out/conv1_weight_r32.mem"}),
      .W3_FILE({`DATA_PATH, "/rns_params_out/conv1_weight_r63.mem"}),
      .B1_FILE({`DATA_PATH, "/rns_params_out/conv1_bias_r31.mem"}),
      .B2_FILE({`DATA_PATH, "/rns_params_out/conv1_bias_r32.mem"}),
      .B3_FILE({`DATA_PATH, "/rns_params_out/conv1_bias_r63.mem"}),
      .OUT_DIR({`DATA_PATH, "/hw_out/"})
  ) u_tb ();
endmodule
