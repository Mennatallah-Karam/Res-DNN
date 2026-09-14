module rns_relu_unit #(
    parameter int N = 5
) (
    input  logic         clk,
    input  logic         rst_n,

    // ---- one PE conv+bias output (rns_pe_unit's out1/out2/out3) per pulse ----
    input  logic [N-1:0] in_mod31,   // out1 (mod 2^N-1 = 31)
    input  logic [N-1:0] in_mod32,   // out2 (mod 2^N   = 32)
    input  logic [N:0]   in_mod63,   // out3 (mod 2^(N+1)-1 = 63)
    input  logic         in_valid,   // = rns_pe_unit's out_valid

    // ---- ReLU'd residue triple, registered one cycle later ----
    output logic [N-1:0] out_mod31,
    output logic [N-1:0] out_mod32,
    output logic [N:0]   out_mod63,
    output logic         out_valid
);

  logic sign;

  rns_sign_detector #(.N(N)) u_sign (
      .x1  (in_mod63),
      .x2  (in_mod31),
      .x3  (in_mod32),
      .sign(sign)
  );


  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_valid <= 1'b0;
      out_mod31 <= '0;
      out_mod32 <= '0;
      out_mod63 <= '0;
    end else begin
      out_valid <= in_valid;
      if (in_valid) begin
        out_mod31 <= sign ? '0 : in_mod31;
        out_mod32 <= sign ? '0 : in_mod32;
        out_mod63 <= sign ? '0 : in_mod63;
      end
    end
  end

endmodule : rns_relu_unit
