module rns_channel_multiplier #(
  parameter int W        = 5,  // 5->mod31, 6->mod63
  parameter bit MERSENNE = 1   // 1: modulus 2^W-1 (x1,x3), 0: modulus 2^W (x2, incl. extended)
) (
  input  logic [W-1:0] in1,
  input  logic [W-1:0] in2,
  output logic [W-1:0] prod
);

  localparam int G = (W + 2) / 2;      // Booth radix-4 groups
  localparam int ACC_WIDTH = 2*W + 4; 

  // ---------------- per-group Booth-encoded rows, plain-shifted into ACC_WIDTH ----------------
  logic [ACC_WIDTH-1:0] row [G];

  genvar j;
  generate
    for (j = 0; j < G; j++) begin : gen_row

      localparam int POS_HIGH = 2*j + 1;
      localparam int POS_MID  = 2*j;
      localparam int POS_LOW  = 2*j - 1;

      logic b_high, b_mid, b_low;
      assign b_high = (POS_HIGH >= W) ? 1'b0 : in2[POS_HIGH];
      assign b_mid  = (POS_MID  >= W) ? 1'b0 : in2[POS_MID];
      assign b_low  = (POS_LOW  <  0) ? 1'b0 : in2[POS_LOW];

      logic [2:0] triplet;
      assign triplet = {b_high, b_mid, b_low};

      // selected multiple of in1 for this Booth group: 0, +-1x, +-2x
      logic signed [W+1:0] selected;
      always_comb begin
        case (triplet)
          3'b000, 3'b111: selected = '0;
          3'b001, 3'b010: selected = {2'b0, in1};
          3'b011:         selected = {1'b0, in1, 1'b0};
          3'b100:         selected = -{1'b0, in1, 1'b0};
          3'b101, 3'b110: selected = -{2'b0, in1};
          default:        selected = '0;
        endcase
      end

      // sign-extend into the wide accumulator, then plain shift into position
      logic signed [ACC_WIDTH-1:0] selected_ext;
      assign selected_ext = ACC_WIDTH'(selected); // sign-extending cast
      assign row[j] = selected_ext <<< (2*j);

    end
  endgenerate

  // ---------------- 4 to 2 compressor, then one plain resolving add ----------------
  logic [ACC_WIDTH-1:0] sum_final, carry_final;

  rns_compressor #(.N(G), .W(ACC_WIDTH)) u_reduce (
    .ops       (row),
    .sum_out   (sum_final),
    .carry_out (carry_final)
  );

  logic [ACC_WIDTH-1:0] full_prod_wide;
  assign full_prod_wide = sum_final + carry_final; 
  logic [2*W-1:0] full_prod;
  assign full_prod = full_prod_wide[2*W-1:0]; 

  generate
    if (MERSENNE) begin : g_mersenne_fold
      // 2^W === 1 (mod 2^W-1)  =>  full_prod === p_hi + p_lo (mod 2^W-1)
      logic [W-1:0] p_hi, p_lo;
      assign p_lo = full_prod[W-1:0];
      assign p_hi = full_prod[2*W-1:W];

      rns_eac_adder #(.W(W)) u_fold (
        .a   (p_hi),
        .b   (p_lo),
        .sum (prod)
      );
    end else begin : g_pow2_truncate
      assign prod = full_prod[W-1:0]; // |a*b|_{2^W}: truncate, drop high bits
    end
  endgenerate

endmodule : rns_channel_multiplier