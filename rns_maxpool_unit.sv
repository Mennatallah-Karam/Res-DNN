module rns_maxpool_unit #(
    parameter int N         = 5,
    parameter int POOL_SIZE = 4    // elements per pooling window (2x2 pool -> 4, 3x3 -> 9)
) (
    input  logic         clk,
    input  logic         rst_n,

    // ---- ReLU output stream: ONE element of the current pooling window per pulse ----
    input  logic [N-1:0] in_mod31,
    input  logic [N-1:0] in_mod32,
    input  logic [N:0]   in_mod63,
    input  logic         in_valid,   // pulse: consume this element
    input  logic         in_first,   // this element is the 1st of a new pooling window
    input  logic         in_last,    // this element is the last of the current pooling window

    // ---- pooled residue triple, one pulse per completed window ----
    output logic [N-1:0] out_mod31,
    output logic [N-1:0] out_mod32,
    output logic [N:0]   out_mod63,
    output logic         out_valid
);

  logic [N-1:0] max1_q, max2_q;
  logic [N:0]   max3_q;

  logic [N-1:0] cmp_max1, cmp_max2;
  logic [N:0]   cmp_max3;

  rns_max_pool #(.N(N)) u_cmp (
      .x1(in_mod31), .y1(max1_q),
      .x2(in_mod32), .y2(max2_q),
      .x3(in_mod63), .y3(max3_q),
      .max_x1(cmp_max1), .max_x2(cmp_max2), .max_x3(cmp_max3),
      .x_is_max(/* unused -- residues are already selected by rns_max_pool */)
  );

  logic [N-1:0] next_max1, next_max2;
  logic [N:0]   next_max3;

  assign next_max1 = in_first ? in_mod31 : cmp_max1;
  assign next_max2 = in_first ? in_mod32 : cmp_max2;
  assign next_max3 = in_first ? in_mod63 : cmp_max3;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      max1_q <= '0; max2_q <= '0; max3_q <= '0;
    end else if (in_valid) begin
      max1_q <= next_max1;
      max2_q <= next_max2;
      max3_q <= next_max3;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_valid <= 1'b0;
      out_mod31 <= '0;
      out_mod32 <= '0;
      out_mod63 <= '0;
    end else begin
      out_valid <= in_valid && in_last;
      if (in_valid && in_last) begin
        out_mod31 <= next_max1;
        out_mod32 <= next_max2;
        out_mod63 <= next_max3;
      end
    end
  end

endmodule : rns_maxpool_unit
