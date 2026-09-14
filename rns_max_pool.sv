module rns_max_pool #(
  parameter int N = 5
) (
  input  logic [N-1:0] x1, y1,        // mod 2^N - 1
  input  logic [N-1:0] x2, y2,        // mod 2^N
  input  logic [N:0]   x3, y3,        // mod 2^(N+1) - 1

  output logic [N-1:0] max_x1,
  output logic [N-1:0] max_x2,
  output logic [N:0]   max_x3,
  output logic         x_is_max        // 1: X selected, 0: Y selected
);

  logic [N-1:0] px1, py1;              // p1(X), p1(Y)  -- mod 2^N-1
  logic [N-1:0] px2, py2;              // p2(X), p2(Y)  -- mod 2^N

  rns_partition_functions #(.N(N)) u_px (
    .x1(x1), .x2(x2), .x3(x3),
    .p1(px1), .p2(px2)
  );

  rns_partition_functions #(.N(N)) u_py (
    .x1(y1), .x2(y2), .x3(y3),
    .p1(py1), .p2(py2)
  );

  // Lexicographic comparison: p1 -> p2 -> x3
  always_comb begin
    if (px1 != py1)
      x_is_max = (px1 > py1);
    else if (px2 != py2)
      x_is_max = (px2 > py2);
    else
      x_is_max = (x3 >= y3);
  end

  assign max_x1 = x_is_max ? x1 : y1;
  assign max_x2 = x_is_max ? x2 : y2;
  assign max_x3 = x_is_max ? x3 : y3;

endmodule : rns_max_pool