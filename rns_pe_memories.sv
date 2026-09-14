module rns_ifmap_mem #(
    parameter int DATA_WIDTH  = 16,
    parameter int DEPTH       = 1024,
    parameter string MEM_FILE = "ifmap_bns.mem"
) (
    input  logic [$clog2(DEPTH)-1:0]     addr,
    output logic signed [DATA_WIDTH-1:0] data
);
  logic signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];
  initial $readmemh(MEM_FILE, mem);
  assign data = mem[addr];
endmodule


// ---- weights: RNS domain, 3 residues, one triple per tap ----
module rns_weight_mem #(
    parameter int DEPTH       = 1024,
    parameter string W1_FILE  = "weight_r31.mem",
    parameter string W2_FILE  = "weight_r32.mem",
    parameter string W3_FILE  = "weight_r63.mem"
) (
    input  logic [$clog2(DEPTH)-1:0] addr,
    output logic [4:0]               w1,
    output logic [4:0]               w2,
    output logic [5:0]               w3
);
  logic [4:0] mem1 [0:DEPTH-1];
  logic [4:0] mem2 [0:DEPTH-1];
  logic [5:0] mem3 [0:DEPTH-1];

  initial begin
    $readmemh(W1_FILE, mem1);
    $readmemh(W2_FILE, mem2);
    $readmemh(W3_FILE, mem3);
  end

  assign w1 = mem1[addr];
  assign w2 = mem2[addr];
  assign w3 = mem3[addr];
endmodule


// ---- bias: RNS domain, 3 residues, one triple per OUTPUT (not per tap) ----
module rns_bias_mem #(
    parameter int DEPTH       = 64,
    parameter string B1_FILE  = "bias_r31.mem",
    parameter string B2_FILE  = "bias_r32.mem",
    parameter string B3_FILE  = "bias_r63.mem"
) (
    input  logic [$clog2(DEPTH)-1:0] addr,
    output logic [4:0]               bias1,
    output logic [4:0]               bias2,
    output logic [5:0]               bias3
);
  logic [4:0] mem1 [0:DEPTH-1];
  logic [4:0] mem2 [0:DEPTH-1];
  logic [5:0] mem3 [0:DEPTH-1];

  initial begin
    $readmemh(B1_FILE, mem1);
    $readmemh(B2_FILE, mem2);
    $readmemh(B3_FILE, mem3);
  end

  assign bias1 = mem1[addr];
  assign bias2 = mem2[addr];
  assign bias3 = mem3[addr];
endmodule


module rns_ifmap_rns_mem #(
    parameter int DEPTH       = 1024,
    parameter string R31_FILE = "ifmap_r31.mem",
    parameter string R32_FILE = "ifmap_r32.mem",
    parameter string R63_FILE = "ifmap_r63.mem"
) (
    input  logic [$clog2(DEPTH)-1:0] addr,
    output logic [4:0]               r31,
    output logic [4:0]               r32,
    output logic [5:0]               r63
);
  logic [4:0] mem31 [0:DEPTH-1];
  logic [4:0] mem32 [0:DEPTH-1];
  logic [5:0] mem63 [0:DEPTH-1];

  initial begin
    $readmemh(R31_FILE, mem31);
    $readmemh(R32_FILE, mem32);
    $readmemh(R63_FILE, mem63);
  end

  assign r31 = mem31[addr];
  assign r32 = mem32[addr];
  assign r63 = mem63[addr];
endmodule

// module rns_ifmap_rns_mem_padded #(
//     parameter int C_IN    = 64,     // Producing layer's NUM_CHANNELS (or flattened feature
//                                      // count, for FC layers -- see rns_pe_top's FC note)
//     parameter int H_IN    = 16,     // Producing layer's H_POOL (1 for FC layers)
//     parameter int W_IN    = 16,     // Producing layer's W_POOL (1 for FC layers)
//     parameter int PAD     = 1,      // Padding amount (KERNEL / 2; 0 for FC layers, KERNEL=1)
//     parameter string R31_FILE = "ifmap_r31.mem",
//     parameter string R32_FILE = "ifmap_r32.mem",
//     parameter string R63_FILE = "ifmap_r63.mem",

//     // ---- derived widths, guarded against the degenerate 1x1 FC case ----
//     // BUG FIXED HERE: the previous version sliced unpadded_row/col down to
//     // [$clog2(H_IN)-1:0] / [$clog2(W_IN)-1:0] BEFORE the multiply. With
//     // H_IN=1 (the FC-layer setting), $clog2(1)=0, making that a [-1:0]
//     // part-select -- an invalid reversed range, which is exactly what
//     // vopt-3373 flagged. Fixed by doing the address arithmetic at full
//     // width and only slicing ONCE, at the very end, down to ADDR_W (itself
//     // guarded to never go below 1 bit).
//     localparam int H_PAD_IN = H_IN + 2*PAD,
//     localparam int W_PAD_IN = W_IN + 2*PAD,
//     localparam int CIN_W    = (C_IN     <= 1) ? 1 : $clog2(C_IN),
//     localparam int ROW_W    = (H_PAD_IN <= 1) ? 1 : $clog2(H_PAD_IN),
//     localparam int COL_W    = (W_PAD_IN <= 1) ? 1 : $clog2(W_PAD_IN),
//     localparam int DEPTH    = C_IN * H_IN * W_IN,
//     localparam int ADDR_W   = (DEPTH    <= 1) ? 1 : $clog2(DEPTH)
// ) (
//     input  logic [CIN_W-1:0] cin,
//     input  logic [ROW_W-1:0] row,   // padded row index
//     input  logic [COL_W-1:0] col,   // padded col index
//     output logic [4:0]       r31,
//     output logic [4:0]       r32,
//     output logic [5:0]       r63
// );

//   logic [4:0] mem31 [0:DEPTH-1];
//   logic [4:0] mem32 [0:DEPTH-1];
//   logic [5:0] mem63 [0:DEPTH-1];

//   initial begin
//     $readmemh(R31_FILE, mem31);
//     $readmemh(R32_FILE, mem32);
//     $readmemh(R63_FILE, mem63);
//   end

//   // Full-width signed arithmetic -- no intermediate variable-width slices.
//   // 32 bits comfortably covers every realistic C_IN*H_IN*W_IN for this
//   // design (FC1's 4096*1*1 and beyond).
//   logic signed [31:0] unpadded_row, unpadded_col;
//   assign unpadded_row = $signed({1'b0, row}) - PAD;
//   assign unpadded_col = $signed({1'b0, col}) - PAD;

//   logic in_range;
//   assign in_range = (unpadded_row >= 0) && (unpadded_row < H_IN) &&
//                      (unpadded_col >= 0) && (unpadded_col < W_IN);

//   logic [31:0] addr_full;
//   assign addr_full = cin * (H_IN * W_IN) + unpadded_row * W_IN + unpadded_col;

//   wire [ADDR_W-1:0] addr = addr_full[ADDR_W-1:0];   // single, always-valid final slice

//   assign r31 = in_range ? mem31[addr] : 5'd0;
//   assign r32 = in_range ? mem32[addr] : 5'd0;
//   assign r63 = in_range ? mem63[addr] : 6'd0;

// endmodule : rns_ifmap_rns_mem_padded

// module rns_output_mem #(
//     parameter int DEPTH = 64
// ) (
//     input  logic       clk,
//     input  logic       rst_n,
//     input  logic [4:0] out1,
//     input  logic [4:0] out2,
//     input  logic [5:0] out3,
//     input  logic       out_valid,

//     output logic [$clog2(DEPTH+1)-1:0] wr_ptr
// );
//   logic [4:0] mem1 [0:DEPTH-1];
//   logic [4:0] mem2 [0:DEPTH-1];
//   logic [5:0] mem3 [0:DEPTH-1];

//   always_ff @(posedge clk or negedge rst_n) begin
//     if (!rst_n) begin
//       wr_ptr <= '0;
//     end else if (out_valid) begin
//       mem1[wr_ptr[$clog2(DEPTH)-1:0]] <= out1;
//       mem2[wr_ptr[$clog2(DEPTH)-1:0]] <= out2;
//       mem3[wr_ptr[$clog2(DEPTH)-1:0]] <= out3;
//       wr_ptr <= wr_ptr + 1'b1;
//     end
//   end

//   // Call from a testbench (after `done`) to dump captured outputs to .mem files.
//   task automatic dump_mem(input string r31_file, input string r32_file, input string r63_file);
//     integer f1, f2, f3, i;
//     f1 = $fopen(r31_file, "w");
//     f2 = $fopen(r32_file, "w");
//     f3 = $fopen(r63_file, "w");
//     for (i = 0; i < wr_ptr; i = i + 1) begin
//       $fwrite(f1, "%02x\n", mem1[i]);
//       $fwrite(f2, "%02x\n", mem2[i]);
//       $fwrite(f3, "%02x\n", mem3[i]);
//     end
//     $fclose(f1);
//     $fclose(f2);
//     $fclose(f3);
//   endtask

// endmodule

// module rns_output_mem_addressed #(
//     parameter int DEPTH = 64
// ) (
//     input  logic                      clk,
//     input  logic                      rst_n,
//     input  logic [4:0]                out1,
//     input  logic [4:0]                out2,
//     input  logic [5:0]                out3,
//     input  logic                      out_valid,
//     input  logic [$clog2(DEPTH)-1:0]  wr_addr,

//     output logic [$clog2(DEPTH+1)-1:0] wr_count   // sanity counter, not an address
// );
//   logic [4:0] mem1 [0:DEPTH-1];
//   logic [4:0] mem2 [0:DEPTH-1];
//   logic [5:0] mem3 [0:DEPTH-1];

//   always_ff @(posedge clk or negedge rst_n) begin
//     if (!rst_n) begin
//       wr_count <= '0;
//     end else if (out_valid) begin
//       mem1[wr_addr] <= out1;
//       mem2[wr_addr] <= out2;
//       mem3[wr_addr] <= out3;
//       wr_count <= wr_count + 1'b1;
//     end
//   end

//   // dumps the full DEPTH range in address order -- wr_count is just for
//   // asserting completeness (should equal DEPTH once `done`), not a bound.
//   task automatic dump_mem(input string r31_file, input string r32_file, input string r63_file);
//     integer f1, f2, f3, i;
//     f1 = $fopen(r31_file, "w");
//     f2 = $fopen(r32_file, "w");
//     f3 = $fopen(r63_file, "w");
//     for (i = 0; i < DEPTH; i = i + 1) begin
//       $fwrite(f1, "%02x\n", mem1[i]);
//       $fwrite(f2, "%02x\n", mem2[i]);
//       $fwrite(f3, "%02x\n", mem3[i]);
//     end
//     $fclose(f1);
//     $fclose(f2);
//     $fclose(f3);
//   endtask
// endmodule

module rns_ifmap_live_padded #(
    parameter int C_IN = 64,
    parameter int H_IN = 16,
    parameter int W_IN = 16,
    parameter int PAD  = 1,

    localparam int H_PAD_IN = H_IN + 2*PAD,
    localparam int W_PAD_IN = W_IN + 2*PAD,
    localparam int CIN_W    = (C_IN     <= 1) ? 1 : $clog2(C_IN),
    localparam int ROW_W    = (H_PAD_IN <= 1) ? 1 : $clog2(H_PAD_IN),
    localparam int COL_W    = (W_PAD_IN <= 1) ? 1 : $clog2(W_PAD_IN),
    localparam int DEPTH    = (C_IN * H_IN * W_IN <= 1) ? 1 : C_IN * H_IN * W_IN,
    localparam int ADDR_W   = (DEPTH    <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic clk,
    input  logic rst_n,

    input  logic [CIN_W-1:0] cin,
    input  logic [ROW_W-1:0] row,   // padded row index
    input  logic [COL_W-1:0] col,   // padded col index

    input  logic [4:0] src_r31 [0:DEPTH-1],
    input  logic [4:0] src_r32 [0:DEPTH-1],
    input  logic [5:0] src_r63 [0:DEPTH-1],

    output logic [4:0] r31,
    output logic [4:0] r32,
    output logic [5:0] r63
);

  // ---- combinational address decode: unchanged -- cheap bounds/
  // arithmetic logic, not the memory read itself. ----
  logic signed [31:0] unpadded_row, unpadded_col;
  assign unpadded_row = $signed({1'b0, row}) - PAD;
  assign unpadded_col = $signed({1'b0, col}) - PAD;

  logic in_range;
  assign in_range = (unpadded_row >= 0) && (unpadded_row < H_IN) &&
                     (unpadded_col >= 0) && (unpadded_col < W_IN);

  logic [31:0] addr_full;
  assign addr_full = cin * (H_IN * W_IN) + unpadded_row * W_IN + unpadded_col;

  wire [ADDR_W-1:0] addr = addr_full[ADDR_W-1:0];
  logic [ADDR_W-1:0] addr_q;
  logic              in_range_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      addr_q     <= '0;
      in_range_q <= 1'b0;
    end else begin
      addr_q     <= addr;
      in_range_q <= in_range;
    end
  end

  assign r31 = in_range_q ? src_r31[addr_q] : 5'd0;
  assign r32 = in_range_q ? src_r32[addr_q] : 5'd0;
  assign r63 = in_range_q ? src_r63[addr_q] : 6'd0;

endmodule : rns_ifmap_live_padded


module rns_act_store #(
    parameter int DEPTH = 64
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [4:0] in1,
    input  logic [4:0] in2,
    input  logic [5:0] in3,
    input  logic       in_valid,

    output logic [4:0] mem1 [0:DEPTH-1],
    output logic [4:0] mem2 [0:DEPTH-1],
    output logic [5:0] mem3 [0:DEPTH-1],

    output logic [$clog2(DEPTH+1)-1:0] wr_ptr
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
    end else if (in_valid) begin
      mem1[wr_ptr[$clog2(DEPTH)-1:0]] <= in1;
      mem2[wr_ptr[$clog2(DEPTH)-1:0]] <= in2;
      mem3[wr_ptr[$clog2(DEPTH)-1:0]] <= in3;
      wr_ptr <= wr_ptr + 1'b1;
    end
  end

endmodule : rns_act_store