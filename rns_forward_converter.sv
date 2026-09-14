module rns_forward_converter #(
  parameter int INPUT_WIDTH = 16,   // 16-bit signed IFmaps, 8-bit signed weights
  parameter int W           = 5
) (
  input  logic [INPUT_WIDTH-1:0] x_bin,
  output logic [W-1:0]           x1,     // mod (2^W - 1)     = 31
  output logic [W-1:0]           x2,     // mod (2^W)         = 32
  output logic [W:0]             x3      // mod (2^(W+1) - 1) = 63
);

  // ---------------- Sign Extractor & Absolute Value (Magnitude) ----------------
  logic sign;
  assign sign = x_bin[INPUT_WIDTH-1];

  logic [INPUT_WIDTH-1:0] mag_bin;
  assign mag_bin = sign ? (~x_bin + 1'b1) : x_bin;   // Two's complement magnitude

  // ---------------- x2: Trivial mod 2^W (lowest W bits) ----------------
  assign x2 = x_bin[W-1:0];

  // ---------------- x1: mod (2^W - 1) = 31 ----------------
  localparam int NUM_CHUNKS_31 = (INPUT_WIDTH + 4) / 5;

  logic [W-1:0] chunks31 [NUM_CHUNKS_31];
  logic [W-1:0] partial31 [NUM_CHUNKS_31];
  logic [W-1:0] mag_residue31;

  always_comb begin
    for (int c = 0; c < NUM_CHUNKS_31; c++) begin
      for (int b = 0; b < 5; b++) begin
        automatic int idx = c * 5 + b;
        chunks31[c][b] = (idx < INPUT_WIDTH) ? mag_bin[idx] : 1'b0;
      end
    end
  end

  genvar gi;
  generate
    assign partial31[0] = chunks31[0];
    for (gi = 1; gi < NUM_CHUNKS_31; gi++) begin : gen_x1_reduce
      rns_eac_adder #(.W(5)) u_add31 (
        .a   (partial31[gi-1]),
        .b   (chunks31[gi]),
        .sum (partial31[gi])
      );
    end
  endgenerate

  assign mag_residue31 = partial31[NUM_CHUNKS_31-1];

  // Mersenne negation mod 31: invert bits, normalize 31 -> 0
  logic [W-1:0] neg_res31;
  assign neg_res31 = ~mag_residue31;
  assign x1 = sign ? ((neg_res31 == 5'd31) ? 5'd0 : neg_res31) 
                   : ((mag_residue31 == 5'd31) ? 5'd0 : mag_residue31);

  // ---------------- x3: mod (2^(W+1) - 1) = 63 ----------------
  localparam int NUM_CHUNKS_63 = (INPUT_WIDTH + 5) / 6;

  logic [W:0] chunks63 [NUM_CHUNKS_63];
  logic [W:0] partial63 [NUM_CHUNKS_63];
  logic [W:0] mag_residue63;

  always_comb begin
    for (int c = 0; c < NUM_CHUNKS_63; c++) begin
      for (int b = 0; b < 6; b++) begin
        automatic int idx = c * 6 + b;
        chunks63[c][b] = (idx < INPUT_WIDTH) ? mag_bin[idx] : 1'b0;
      end
    end
  end

  generate
    assign partial63[0] = chunks63[0];
    for (gi = 1; gi < NUM_CHUNKS_63; gi++) begin : gen_x3_reduce
      rns_eac_adder #(.W(6)) u_add63 (
        .a   (partial63[gi-1]),
        .b   (chunks63[gi]),
        .sum (partial63[gi])
      );
    end
  endgenerate

  assign mag_residue63 = partial63[NUM_CHUNKS_63-1];

  // Mersenne negation mod 63: invert bits, normalize 63 -> 0
  logic [W:0] neg_res63;
  assign neg_res63 = ~mag_residue63;
  assign x3 = sign ? ((neg_res63 == 6'd63) ? 6'd0 : neg_res63) 
                   : ((mag_residue63 == 6'd63) ? 6'd0 : mag_residue63);

endmodule : rns_forward_converter