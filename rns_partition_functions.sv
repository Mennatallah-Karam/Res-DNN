module rns_partition_functions #(
  parameter int N = 5
) (
  input  logic [N-1:0] x1,      // mod 2^N - 1 , range [0 .. 2^N-2]
  input  logic [N-1:0] x2,      // mod 2^N     , range [0 .. 2^N-1]
  input  logic [N:0]   x3,      // mod 2^(N+1)-1 , range [0 .. 2^(N+1)-2]
  output logic [N-1:0] p1,      // canonical, mod 2^N - 1
  output logic [N-1:0] p2       // canonical, mod 2^N
);

  assign p2 = x3[N-1:0] - x2;

  logic [N-1:0] x3_mod_m1;
  logic [N:0]   x3_fold_raw;
  assign x3_fold_raw = {1'b0, x3[N-1:0]} + x3[N];
  assign x3_mod_m1   = (x3_fold_raw[N-1:0] + x3_fold_raw[N]); // second EAC pass

  logic [N-1:0] p1_stage1;
  logic [N-1:0] p1_final;

  // Stage 1: x1 + ~x3_mod_m1, mod (2^N-1) via EAC
  logic [N:0] s1_raw;
  assign s1_raw    = {1'b0, x1} + {1'b0, ~x3_mod_m1};
  assign p1_stage1 = s1_raw[N-1:0] + s1_raw[N];

  // Stage 2: stage1 + ~p2, mod (2^N-1) via EAC
  logic [N:0] s2_raw;
  assign s2_raw    = {1'b0, p1_stage1} + {1'b0, ~p2};
  assign p1_final  = s2_raw[N-1:0] + s2_raw[N];

  // Canonicalize the redundant all-ones representation of 0.
  assign p1 = (p1_final == {N{1'b1}}) ? '0 : p1_final;

endmodule : rns_partition_functions