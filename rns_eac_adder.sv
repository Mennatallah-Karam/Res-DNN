module rns_eac_adder #(
  parameter int W = 5  // W=5 for mod 31, W=6 for mod 63
) (
  input  logic [W-1:0] a,
  input  logic [W-1:0] b,
  output logic [W-1:0] sum  // |a+b| mod (2^W-1)
);

  localparam int L = $clog2(W); // number of Sklansky combine levels

  // ---------------- bit-level generate/propagate ----------------
  logic [W-1:0] g0, p0;
  assign g0 = a & b;
  assign p0 = a ^ b;

  // ---------------- Sklansky prefix tree ----------------
  logic [W-1:0] Glvl [0:L];
  logic [W-1:0] Plvl [0:L];

  assign Glvl[0] = g0;
  assign Plvl[0] = p0;

  genvar lvl, i;
  generate
    for (lvl = 1; lvl <= L; lvl++) begin : gen_level
      for (i = 0; i < W; i++) begin : gen_bit
        if ((i - ((i / (1 << lvl)) * (1 << lvl))) >= (1 << (lvl - 1))) begin : combine
          localparam int BOUND = ((i / (1 << lvl)) * (1 << lvl)) + (1 << (lvl - 1)) - 1;
          assign Glvl[lvl][i] = Glvl[lvl-1][i] | (Plvl[lvl-1][i] & Glvl[lvl-1][BOUND]);
          assign Plvl[lvl][i] = Plvl[lvl-1][i] & Plvl[lvl-1][BOUND];
        end else begin : passthrough
          assign Glvl[lvl][i] = Glvl[lvl-1][i];
          assign Plvl[lvl][i] = Plvl[lvl-1][i];
        end
      end
    end
  endgenerate

  logic G_total, P_total, cin;
  assign G_total = Glvl[L][W-1];
  assign P_total = Plvl[L][W-1];
  assign cin     = G_total | P_total; // end-around carry-in

  logic [W-1:0] carry_in_bit;
  generate
    for (i = 0; i < W; i++) begin : gen_sum
      if (i == 0)
        assign carry_in_bit[i] = cin;
      else
        assign carry_in_bit[i] = Glvl[L][i-1] | (Plvl[L][i-1] & cin);
    end
  endgenerate

  logic [W-1:0] raw_sum;
  assign raw_sum = p0 ^ carry_in_bit;
  assign sum = (raw_sum == '1) ? '0 : raw_sum; // fold all-ones to canonical zero

endmodule : rns_eac_adder