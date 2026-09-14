module rns_base_extension #(
  parameter int E = 3
) (
  input  logic [4:0]     x1,      // mod (2^5 - 1) = 31
  input  logic [4:0]     x2,      // mod  2^5      = 32  (channel being extended)
  input  logic [5:0]     x3,      // mod (2^6 - 1) = 63
  output logic [4+E:0]   x2_ext   // mod 2^(5+E), signed-centered reconstruction
);

  localparam int unsigned M_PRIMARY = 31 * 32 * 63; // 62496
  localparam int unsigned M_HALF    = M_PRIMARY / 2; // 31248

  // ---------------- a2 = |x1 - x2|_31 ----------------
  logic [4:0] a2;
  rns_eac_adder #(.W(5)) u_a2 (.a(x1), .b(~x2), .sum(a2));

  // ---------------- CSA inputs, rotate-fed (free wiring for 4x/2x) ----------------
  logic [5:0] x3_x4_rot;
  assign x3_x4_rot = {x3[3:0], x3[5:4]};        // 4*x3 mod 63

  logic [5:0] x2_6, x2_x4_rot;
  assign x2_6 = {1'b0, x2};
  assign x2_x4_rot = {x2_6[3:0], x2_6[5:4]};    // 4*x2 mod 63

  logic [5:0] a2_6, a2_x2_rot;
  assign a2_6 = {1'b0, a2};
  assign a2_x2_rot = {a2_6[4:0], a2_6[5]};      // 2*a2 mod 63

  // ---------------- CSA: 3:2 compress (per-bit, no carry chain) ----------------
  logic [5:0] csa_A, csa_B, csa_C;
  assign csa_A = x3_x4_rot;
  assign csa_B = ~x2_x4_rot;
  assign csa_C = ~a2_x2_rot;

  logic [5:0] S0, C0;
  assign S0 = csa_A ^ csa_B ^ csa_C;
  assign C0 = (csa_A & csa_B) | (csa_B & csa_C) | (csa_A & csa_C);

  logic [5:0] C0_aligned;
  assign C0_aligned = {C0[4:0], C0[5]}; // weight-2 alignment = rotate-by-1 in mod-63 domain

  // ---------------- resolve to canonical abar3 (one EAC fold) ----------------
  logic [5:0] abar3;
  rns_eac_adder #(.W(6)) u_resolve (.a(S0), .b(C0_aligned), .sum(abar3));

  // ---------------- a3 = |-abar3|_63 (negate to recover TRUE a3) ----------------
  logic [5:0] a3;
  rns_eac_adder #(.W(6)) u_negate (.a(6'b0), .b(~abar3), .sum(a3));

  // ---------------- 31*a3 = (a3<<5) - a3, exact integer arithmetic ----------------
  logic [10:0] term_31a3;
  assign term_31a3 = ({a3, 5'b0}) - {5'b0, a3};

  logic [11:0] y_wide;
  assign y_wide = {7'b0, a2} + {1'b0, term_31a3};   // y_wide = a2 + 31*a3

  // ---------------- Full uncentered MRC value: V = 32*y_wide + x2 ----------------
  logic [15:0] V_full;
  assign V_full = {y_wide, 5'b0} + {11'b0, x2};     // (y_wide << 5) + x2, range [0, 62495]

  // ---------------- Centering: true_V = (V >= M/2) ? V - M_PRIMARY : V ----------------
  logic signed [17:0] true_V;
  assign true_V = (V_full >= M_HALF[15:0])
                    ? ($signed({2'b0, V_full}) - $signed(18'(M_PRIMARY)))
                    : $signed({2'b0, V_full});

  // ---------------- x2_ext = true_V mod 2^(5+E) = low (5+E) bits, two's-complement ----------------
  assign x2_ext = true_V[4+E:0];

endmodule : rns_base_extension