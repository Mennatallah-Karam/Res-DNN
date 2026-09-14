module rns_compressor #(
  parameter int N = 3,
  parameter int W = 11
) (
  input  var  logic [W-1:0] ops [N],
  output      logic [W-1:0] sum_out,
  output      logic [W-1:0] carry_out
);

  generate
    if (N == 1) begin : g_n1
      assign sum_out   = ops[0];
      assign carry_out = '0;
    end else if (N == 2) begin : g_n2
      assign sum_out   = ops[0];
      assign carry_out = ops[1];
    end else begin : g_reduce
      logic [W-1:0] s, c, c_aligned;
      assign s = ops[0] ^ ops[1] ^ ops[2];
      assign c = (ops[0] & ops[1]) | (ops[1] & ops[2]) | (ops[0] & ops[2]);
      assign c_aligned = {c[W-2:0], 1'b0}; // plain shift-left-1, no wraparound

      logic [W-1:0] next_ops [N-1];
      assign next_ops[0] = s;
      assign next_ops[1] = c_aligned;

      genvar k;
      for (k = 3; k < N; k++) begin : g_passthrough
        assign next_ops[k-1] = ops[k];
      end

      rns_compressor #(.N(N-1), .W(W)) u_recurse (
        .ops       (next_ops),
        .sum_out   (sum_out),
        .carry_out (carry_out)
      );
    end
  endgenerate

endmodule : rns_compressor