module rns_scaling_unit #(
  parameter int E = 3   
) (
  input  logic [4:0]   x1,    // mod (2^5 - 1) = 31
  input  logic [4+E:0] x2,    // mod  2^(5+E)   (channel being reduced)
  input  logic [5:0]   x3,    // mod (2^6 - 1) = 63
  output logic [4:0]   xS1,   // mod 31, scaled
  output logic [4:0]   xS2,   // mod 32, scaled
  output logic [5:0]   xS3    // mod 63, scaled
);

  // ---------------- |x2|_{2^E}: trivially the low E bits of x2 ----------------
  logic [E-1:0] x2_low;
  assign x2_low = x2[E-1:0];

  // ---------------- fold x2_low into mod-31 and mod-63 domains ----------------
  logic [4:0] x2_low_mod31;
  logic [5:0] x2_low_mod63;
  rns_mod_reduce #(.IN_WIDTH(E), .W(5)) u_reduce31 (.in_val(x2_low), .out_val(x2_low_mod31));
  rns_mod_reduce #(.IN_WIDTH(E), .W(6)) u_reduce63 (.in_val(x2_low), .out_val(x2_low_mod63));

  // ---------------- |x1 - |x2|_{2^E}|_31  and  |x3 - |x2|_{2^E}|_63 ----------------
  logic [4:0] diff1;
  logic [5:0] diff3;
  rns_eac_adder #(.W(5)) u_sub1 (.a(x1), .b(~x2_low_mod31), .sum(diff1));
  rns_eac_adder #(.W(6)) u_sub3 (.a(x3), .b(~x2_low_mod63), .sum(diff3));

  // ---------------- E-bit right-rotate (mod (2^W-1) division-by-2^E) ----------------
  localparam int ROT1 = E % 5;
  localparam int ROT3 = E % 6;

  assign xS1 = 5'((diff1 >> ROT1) | (diff1 << (5 - ROT1)));
  assign xS3 = 6'((diff3 >> ROT3) | (diff3 << (6 - ROT3)));

  // ---------------- xS2: truncating shift, drop the low E bits ----------------
  assign xS2 = x2[4+E:E];

endmodule : rns_scaling_unit
