module rns_sign_detector #(
    parameter integer N = 5
) (
    input  logic [N:0]   x1,
    input  logic [N-1:0] x2,
    input  logic [N-1:0] x3,
    output logic         sign
);

    wire         x1_top = x1[N];
    wire [N-1:0] x1p    = x1[N-1:0];
    wire [N-2:0] x1_low = x1[N-2:0];

    wire ge = (x2 >= x1p);
    wire gt = (x2 >  x1p);
    wire W  = x1_top ? gt : ge;

    wire [N-1:0] x1pp     = {x1_low, x1_top};
    wire [N-1:0] x1pp_bar = ~x1pp;

    wire [N-1:0] csa_sum   = x1pp_bar ^ x2 ^ x3;
    wire [N-1:0] csa_carry = (x1pp_bar & x2) | (x2 & x3) | (x1pp_bar & x3);

    wire [N:0]   carry_shifted = {csa_carry, 1'b0};
    wire [N:0]   sum_ext       = {1'b0, csa_sum};
    wire [N+1:0] final_sum     = sum_ext + carry_shifted + {{N{1'b0}}, W};

    assign sign = final_sum[N-1];

endmodule