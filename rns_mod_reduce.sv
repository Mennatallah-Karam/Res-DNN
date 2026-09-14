module rns_mod_reduce #(
  parameter int IN_WIDTH = 6,  // width of the value to be reduced
  parameter int W        = 5   // target modulus width; modulus = 2^W - 1
) (
  input  logic [IN_WIDTH-1:0] in_val,
  output logic [W-1:0]        out_val   
);

  localparam int NUM_CHUNKS = (IN_WIDTH + W - 1) / W;  // ceil(IN_WIDTH/W)

  logic [W-1:0] chunks  [NUM_CHUNKS];
  logic [W-1:0] partial [NUM_CHUNKS];

  always_comb begin
    for (int c = 0; c < NUM_CHUNKS; c++) begin
      for (int b = 0; b < W; b++) begin
        automatic int idx;
        idx = c*W + b;
        chunks[c][b] = (idx < IN_WIDTH) ? in_val[idx] : 1'b0;
      end
    end
  end

  genvar gi;
  generate
    assign partial[0] = chunks[0];
    for (gi = 1; gi < NUM_CHUNKS; gi++) begin : gen_reduce
      rns_eac_adder #(.W(W)) u_add (
        .a   (partial[gi-1]),
        .b   (chunks[gi]),
        .sum (partial[gi])
      );
    end
  endgenerate

  assign out_val = partial[NUM_CHUNKS-1];

endmodule : rns_mod_reduce
