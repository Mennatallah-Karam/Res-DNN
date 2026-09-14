`timescale 1ns/1ps
//vsim -c -do "run -all" tb_alexnet_top -l sim_output.log
`define DATA_PATH "D:/NU/RA/full_ResDNN"
module tb_alexnet_top;

  localparam int CLK_PERIOD = 10;
  localparam int NUM_LAYERS = 8;

  logic clk = 0;
  logic rst_n;
  logic start;
  logic done;

  always #(CLK_PERIOD/2) clk = ~clk;

  rns_alexnet_top #(
      .DATA_PATH(`DATA_PATH)
  ) dut (
      .clk(clk), .rst_n(rst_n), .start(start), .done(done)
  );

  // ---- progress trace: print the moment each layer's own done fires ----
  // (dut.done_vec[i] is driven by rns_pe_top_chained's act_wr_ptr==OUT_DEPTH
  // check, not the controller's DRAIN_CYCLES-based done -- see that
  // module's header comment for why.)
  localparam string LAYER_NAME [0:NUM_LAYERS-1] = '{
      "conv1", "conv2", "conv3", "conv4", "conv5", "fc1", "fc2", "fc3"
  };

  logic [NUM_LAYERS-1:0] done_vec_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) done_vec_q <= '0;
    else        done_vec_q <= dut.done_vec;
  end

  genvar gi;
  generate
    for (gi = 0; gi < NUM_LAYERS; gi = gi + 1) begin : g_trace
      always_ff @(posedge clk) begin
        if (dut.done_vec[gi] && !done_vec_q[gi]) begin
          $display("[TB] t=%0t  %s done  (act_depth=%0d)",
                    $time, LAYER_NAME[gi], dut.g_layer[gi].g_inst.u_layer.OUT_DEPTH);
        end
      end
    end
  endgenerate

  // ---- watchdog: bail out with diagnostics if the chain stalls, rather
  // than hanging the simulator silently ----
  localparam longint WATCHDOG_CYCLES = 64'd500_000_000;   // generous given FC layer sizes above
  longint cyc;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) cyc <= 0;
    else        cyc <= cyc + 1;
  end

  initial begin
    rst_n = 0;
    start = 0;
    repeat (4) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    start = 1;
    @(posedge clk);
    start = 0;

    fork
      begin : wait_done
        wait (done);
      end
      begin : watchdog
        wait (cyc > WATCHDOG_CYCLES);
        $display("[TB] WATCHDOG TIMEOUT at t=%0t (cyc=%0d) -- chain stalled.", $time, cyc);
        $display("[TB] done_vec = %b  (bit i set once layer %0s..%0s's activations landed)",
                  dut.done_vec, LAYER_NAME[0], LAYER_NAME[NUM_LAYERS-1]);
        $finish;
      end
    join_any
    disable fork;

    // let the final activation write's NBA settle, same margin as
    // tb_rns_pe_top used around its own wr_ptr wait.
    @(posedge clk);
    @(posedge clk);

    // ---- dump fc3's raw output residues: 10 classes, no ReLU (signed logits) ----
    begin
      int f1, f2, f3;
      string p1, p2, p3;
      p1 = {`DATA_PATH, "/hw_out/alexnet_fc3_logits_r31.mem"};
      p2 = {`DATA_PATH, "/hw_out/alexnet_fc3_logits_r32.mem"};
      p3 = {`DATA_PATH, "/hw_out/alexnet_fc3_logits_r63.mem"};
      f1 = $fopen(p1, "w");
      f2 = $fopen(p2, "w");
      f3 = $fopen(p3, "w");
      for (int k = 0; k < 10; k = k + 1) begin
        $fwrite(f1, "%02x\n", dut.g_layer[7].g_inst.u_layer.out_r31[k]);
        $fwrite(f2, "%02x\n", dut.g_layer[7].g_inst.u_layer.out_r32[k]);
        $fwrite(f3, "%02x\n", dut.g_layer[7].g_inst.u_layer.out_r63[k]);
      end
      $fclose(f1);
      $fclose(f2);
      $fclose(f3);
      $display("[TB] Wrote 10 fc3 logit residue(s) to %s / %s / %s", p1, p2, p3);
    end

    $display("[TB] Full chain (conv1..fc3) complete at t=%0t.", $time);
    $finish;
  end

endmodule : tb_alexnet_top