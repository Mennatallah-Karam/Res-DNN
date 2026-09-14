module rns_conv_relu_pool_layer #(
    parameter int INPUT_WIDTH = 16,
    parameter int K_MUL       = 3,
    parameter int K_ADD       = 6,
    parameter int N           = 5,
    parameter int POOL_SIZE   = 4,   // 1 = no pooling (conv3/conv4), 4 = 2x2 pool (conv1/2/5)
    parameter int CTRL_FIFO_DEPTH = 4,
    parameter int PIX_ADDR_W = 1,
    parameter bit IFMAP_IS_RNS = 0,   // 0: ifmap_bin raw BNS (conv1). 1: ifmap_r31/32/63 residues (conv2+).
    parameter bit APPLY_RELU = 1      // 0: skip ReLU entirely 
) (
    input  logic                          clk,
    input  logic                          rst_n,

    input  logic signed [INPUT_WIDTH-1:0] ifmap_bin,
    input  logic [4:0]                    ifmap_r31,
    input  logic [4:0]                    ifmap_r32,
    input  logic [5:0]                    ifmap_r63,

    input  logic [4:0]                    w1,
    input  logic [4:0]                    w2,
    input  logic [5:0]                    w3,
    input  logic [4:0]                    bias1,
    input  logic [4:0]                    bias2,
    input  logic [5:0]                    bias3,
    input  logic                          mac_valid,
    input  logic                          last_mac,
    input  logic                          reset_accum,

    input  logic                          pool_first,
    input  logic                          pool_last,
    input  logic [PIX_ADDR_W-1:0]         pixel_addr,

    output logic [4:0]                    conv_out_mod31,
    output logic [4:0]                    conv_out_mod32,
    output logic [5:0]                    conv_out_mod63,
    output logic                          conv_out_valid,
    output logic [PIX_ADDR_W-1:0]         conv_out_addr,

    output logic [N-1:0]                  relu_dbg_mod31,
    output logic [N-1:0]                  relu_dbg_mod32,
    output logic [N:0]                    relu_dbg_mod63,
    output logic                          relu_dbg_valid,
    output logic [PIX_ADDR_W-1:0]         relu_out_addr, 

    // ---- pooled (or, if POOL_SIZE=1, pass-through) layer output ----
    output logic [N-1:0]                  out_mod31,
    output logic [N-1:0]                  out_mod32,
    output logic [N:0]                    out_mod63,
    output logic                          out_valid,
    output logic                          busy
);

  logic [4:0] pe_out1;
  logic [4:0] pe_out2;
  logic [5:0] pe_out3;
  logic       pe_out_valid;
  logic       pe_busy;

  rns_pe_unit #(
      .INPUT_WIDTH(INPUT_WIDTH), .K_MUL(K_MUL), .K_ADD(K_ADD), .IFMAP_IS_RNS(IFMAP_IS_RNS)
  ) u_pe (
      .clk(clk), .rst_n(rst_n),
      .ifmap_bin(ifmap_bin),
      .ifmap_r31(ifmap_r31), .ifmap_r32(ifmap_r32), .ifmap_r63(ifmap_r63),
      .w1(w1), .w2(w2), .w3(w3),
      .bias1(bias1), .bias2(bias2), .bias3(bias3),
      .mac_valid(mac_valid), .last_mac(last_mac), .reset_accum(reset_accum),
      .out1(pe_out1), .out2(pe_out2), .out3(pe_out3),
      .out_valid(pe_out_valid), .busy(pe_busy)
  );

  assign conv_out_mod31 = pe_out1;
  assign conv_out_mod32 = pe_out2;
  assign conv_out_mod63 = pe_out3;
  assign conv_out_valid = pe_out_valid;

  logic pool_first_fifo [0:CTRL_FIFO_DEPTH-1];
  logic pool_last_fifo  [0:CTRL_FIFO_DEPTH-1];
  logic [PIX_ADDR_W-1:0] pixel_addr_fifo [0:CTRL_FIFO_DEPTH-1];   // <-- new
  logic [$clog2(CTRL_FIFO_DEPTH)-1:0] ctrl_wr_ptr, ctrl_rd_ptr;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_wr_ptr <= '0;
    end else if (mac_valid && reset_accum) begin
      pool_first_fifo[ctrl_wr_ptr] <= pool_first;
      pool_last_fifo[ctrl_wr_ptr]  <= pool_last;
      pixel_addr_fifo[ctrl_wr_ptr] <= pixel_addr;              // <-- new
      ctrl_wr_ptr <= ctrl_wr_ptr + 1'b1;
    end
  end

  // conv debug tap fires the SAME cycle as pe_out_valid -> combinational
  // read at the current FIFO head, before it's popped.
  assign conv_out_addr = pixel_addr_fifo[ctrl_rd_ptr];          // <-- new

  logic pool_first_q, pool_last_q;
  logic [PIX_ADDR_W-1:0] pixel_addr_q;                          // <-- new

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_rd_ptr  <= '0;
      pool_first_q <= 1'b0;
      pool_last_q  <= 1'b0;
    end else if (pe_out_valid) begin
      pool_first_q <= pool_first_fifo[ctrl_rd_ptr];
      pool_last_q  <= pool_last_fifo[ctrl_rd_ptr];
      pixel_addr_q <= pixel_addr_fifo[ctrl_rd_ptr];              // <-- new
      ctrl_rd_ptr  <= ctrl_rd_ptr + 1'b1;
    end
  end

  assign relu_out_addr = pixel_addr_q;                           // <-- new, aligned with relu_dbg_valid

  logic [4:0] relu_mod31, relu_mod32;
  logic [5:0] relu_mod63;
  logic       relu_valid;

  generate
    if (APPLY_RELU) begin : g_relu
      rns_relu_unit #(.N(N)) u_relu (
          .clk(clk), .rst_n(rst_n),
          .in_mod31(pe_out1), .in_mod32(pe_out2), .in_mod63(pe_out3),
          .in_valid(pe_out_valid),
          .out_mod31(relu_mod31), .out_mod32(relu_mod32), .out_mod63(relu_mod63),
          .out_valid(relu_valid)
      );
    end else begin : g_no_relu
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          relu_valid <= 1'b0;
          relu_mod31 <= '0; relu_mod32 <= '0; relu_mod63 <= '0;
        end else begin
          relu_valid <= pe_out_valid;
          if (pe_out_valid) begin
            relu_mod31 <= pe_out1;
            relu_mod32 <= pe_out2;
            relu_mod63 <= pe_out3;
          end
        end
      end
    end
  endgenerate

  assign relu_dbg_mod31 = relu_mod31;
  assign relu_dbg_mod32 = relu_mod32;
  assign relu_dbg_mod63 = relu_mod63;
  assign relu_dbg_valid = relu_valid;

  rns_maxpool_unit #(.N(N), .POOL_SIZE(POOL_SIZE)) u_pool (
      .clk(clk), .rst_n(rst_n),
      .in_mod31(relu_mod31), .in_mod32(relu_mod32), .in_mod63(relu_mod63),
      .in_valid(relu_valid),
      .in_first(pool_first_q),
      .in_last(pool_last_q),
      .out_mod31(out_mod31), .out_mod32(out_mod32), .out_mod63(out_mod63),
      .out_valid(out_valid)
  );

  assign busy = pe_busy | relu_valid;
endmodule : rns_conv_relu_pool_layer