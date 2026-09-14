module rns_pe_controller #(
    parameter int C_IN          = 3,     // input channels per tap group
    parameter int KERNEL        = 3,     // conv kernel size (square)
    parameter int NUM_CHANNELS  = 64,    // output channels
    parameter int H_OUT         = 32,    // conv output height (pre-pool)
    parameter int W_OUT         = 32,    // conv output width  (pre-pool)
    parameter int POOL_KERNEL   = 2,     // pooling window size (square, non-overlapping)
    parameter int DRAIN_CYCLES  = 6,

    // ---- derived (do not override unless you know what you're doing) ----
    parameter int NUM_TAPS      = C_IN * KERNEL * KERNEL,
    parameter int H_PAD         = H_OUT + KERNEL - 1,
    parameter int W_PAD         = W_OUT + KERNEL - 1,
    parameter int H_POOL        = H_OUT / POOL_KERNEL,
    parameter int W_POOL        = W_OUT / POOL_KERNEL,
    parameter int NUM_WINDOWS   = H_POOL * W_POOL,
    parameter int POOL_SIZE     = POOL_KERNEL * POOL_KERNEL,

    parameter int CW            = (C_IN                          <= 1) ? 1 : $clog2(C_IN),
    parameter int WEIGHT_ADDR_W = (NUM_CHANNELS * NUM_TAPS        <= 1) ? 1 : $clog2(NUM_CHANNELS * NUM_TAPS),
    parameter int IFMAP_ADDR_W  = (C_IN * H_PAD * W_PAD           <= 1) ? 1 : $clog2(C_IN * H_PAD * W_PAD),
    parameter int OUT_ADDR_W    = (NUM_CHANNELS                   <= 1) ? 1 : $clog2(NUM_CHANNELS),
    parameter int PIX_ADDR_W    = (NUM_CHANNELS * H_OUT * W_OUT   <= 1) ? 1 : $clog2(NUM_CHANNELS * H_OUT * W_OUT),
    parameter int ROW_W         = (H_PAD                          <= 1) ? 1 : $clog2(H_PAD),
    parameter int COL_W         = (W_PAD                          <= 1) ? 1 : $clog2(W_PAD)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,

    output logic                        mem_rd_en,
    output logic [IFMAP_ADDR_W-1:0]     ifmap_rd_addr,
    output logic [WEIGHT_ADDR_W-1:0]    weight_rd_addr,
    output logic [OUT_ADDR_W-1:0]       bias_rd_addr,

    output logic                        mac_valid,
    output logic                        last_mac,
    output logic                        reset_accum,

    // ---- pooling-window boundary strokes, one pulse-pair per PE output ----
    output logic                        pool_first,
    output logic                        pool_last,
    output logic [PIX_ADDR_W-1:0]       pixel_addr,
    output logic [CW-1:0]               ifmap_cin,
    output logic [ROW_W-1:0]            ifmap_row,
    output logic [COL_W-1:0]            ifmap_col,

    output logic                        busy,
    output logic                        done
);

  localparam int KW  = (KERNEL       <= 1) ? 1 : $clog2(KERNEL);
  localparam int EW  = (POOL_KERNEL  <= 1) ? 1 : $clog2(POOL_KERNEL);
  localparam int WRW = (W_POOL       <= 1) ? 1 : $clog2(W_POOL);
  localparam int HRW = (H_POOL       <= 1) ? 1 : $clog2(H_POOL);
  localparam int CHW = (NUM_CHANNELS <= 1) ? 1 : $clog2(NUM_CHANNELS);
  // or_row/or_col span 0..H_OUT-1 / 0..W_OUT-1 -- same guard needed for
  // FC layers (H_OUT=W_OUT=1).
  localparam int ORW = (H_OUT <= 1) ? 1 : $clog2(H_OUT);
  localparam int OCW = (W_OUT <= 1) ? 1 : $clog2(W_OUT);
  // tap_offset spans 0..NUM_TAPS-1 -- guarded for the same reason, though
  // NUM_TAPS=1 is unlikely in practice (would mean C_IN=KERNEL=1).
  localparam int TOW = (NUM_TAPS <= 1) ? 1 : $clog2(NUM_TAPS);

  typedef enum logic [1:0] {IDLE, RUN, DRAIN} state_t;
  state_t state;

  // ---- tap-position nested counters (innermost -> outermost: kc, kr, cin) ----
  logic [KW-1:0] kc, kr;
  logic [CW-1:0] cin;

  // ---- window-element nested counters (innermost -> outermost: el_c, el_r) ----
  logic [EW-1:0] el_c, el_r;

  // ---- pooling-window nested counters (innermost -> outermost: win_c, win_r) ----
  logic [WRW-1:0] win_c;
  logic [HRW-1:0] win_r;

  // ---- output channel counter ----
  logic [CHW-1:0] ch;

  logic [$clog2(DRAIN_CYCLES+1)-1:0] drain_cnt;

  // ---- combinational "am I at a boundary" flags for the CURRENT cycle ----
  wire tap_is_first  = (kc == 0) && (kr == 0) && (cin == 0);
  wire tap_is_last   = (kc == KERNEL-1) && (kr == KERNEL-1) && (cin == C_IN-1);
  wire elem_is_last  = tap_is_last && (el_c == POOL_KERNEL-1) && (el_r == POOL_KERNEL-1);
  wire window_is_last = elem_is_last && (win_c == W_POOL-1) && (win_r == H_POOL-1);
  wire channel_is_last = window_is_last && (ch == NUM_CHANNELS-1);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= IDLE;
      kc        <= '0;
      kr        <= '0;
      cin       <= '0;
      el_c      <= '0;
      el_r      <= '0;
      win_c     <= '0;
      win_r     <= '0;
      ch        <= '0;
      drain_cnt <= '0;
    end else begin
      case (state)
        IDLE: begin
          if (start) begin
            state <= RUN;
            kc    <= '0;
            kr    <= '0;
            cin   <= '0;
            el_c  <= '0;
            el_r  <= '0;
            win_c <= '0;
            win_r <= '0;
            ch    <= '0;
          end
        end

        RUN: begin
          // ---- innermost carry chain: kc -> kr -> cin -> el_c -> el_r ->
          //      win_c -> win_r -> ch. Each level only advances when every
          //      level below it has wrapped back to 0 this cycle.
          if (kc == KERNEL-1) begin
            kc <= '0;
            if (kr == KERNEL-1) begin
              kr <= '0;
              if (cin == C_IN-1) begin
                cin <= '0;
                // tap loop wrapped: this PE output's last tap just fired
                if (el_c == POOL_KERNEL-1) begin
                  el_c <= '0;
                  if (el_r == POOL_KERNEL-1) begin
                    el_r <= '0;
                    // window's 4 elements done
                    if (win_c == W_POOL-1) begin
                      win_c <= '0;
                      if (win_r == H_POOL-1) begin
                        win_r <= '0;
                        // all windows for this channel done
                        if (ch != NUM_CHANNELS-1) begin
                          ch <= ch + 1'b1;
                        end
                        // if ch == NUM_CHANNELS-1 this is the very last tap
                        // overall -- state transition to DRAIN handled below
                      end else begin
                        win_r <= win_r + 1'b1;
                      end
                    end else begin
                      win_c <= win_c + 1'b1;
                    end
                  end else begin
                    el_r <= el_r + 1'b1;
                  end
                end else begin
                  el_c <= el_c + 1'b1;
                end
              end else begin
                cin <= cin + 1'b1;
              end
            end else begin
              kr <= kr + 1'b1;
            end
          end else begin
            kc <= kc + 1'b1;
          end

          if (channel_is_last) begin
            state     <= DRAIN;
            drain_cnt <= '0;
          end
        end

        DRAIN: begin
          drain_cnt <= drain_cnt + 1'b1;
          if (drain_cnt == DRAIN_CYCLES - 1) state <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end

  wire [ORW-1:0] or_row = win_r * POOL_KERNEL + el_r;   // output-pixel row, pre-pool
  wire [OCW-1:0] or_col = win_c * POOL_KERNEL + el_c;   // output-pixel col, pre-pool

  wire [PIX_ADDR_W-1:0] pixel_addr_comb = ch * (H_OUT * W_OUT) + or_row * W_OUT + or_col;
  assign pixel_addr = pixel_addr_comb;

  wire [IFMAP_ADDR_W-1:0] ifmap_addr_comb =
      cin * (H_PAD * W_PAD) + (or_row + kr) * W_PAD + (or_col + kc);

  wire [TOW-1:0] tap_offset = cin * (KERNEL*KERNEL) + kr * KERNEL + kc;
  wire [WEIGHT_ADDR_W-1:0] weight_addr_comb = ch * NUM_TAPS + tap_offset;

  assign ifmap_rd_addr  = ifmap_addr_comb;
  assign weight_rd_addr = weight_addr_comb;
  assign bias_rd_addr   = ch;
  assign ifmap_cin = cin;
  assign ifmap_row = or_row + kr;
  assign ifmap_col = or_col + kc;

  assign mem_rd_en    = (state == RUN);
  assign mac_valid    = (state == RUN);
  assign last_mac     = (state == RUN) && tap_is_last;
  assign reset_accum  = (state == RUN) && tap_is_first;

  assign pool_first = (el_c == 0) && (el_r == 0);
  assign pool_last  = (el_c == POOL_KERNEL-1) && (el_r == POOL_KERNEL-1);

  assign busy = (state != IDLE);
  assign done = (state == DRAIN) && (drain_cnt == DRAIN_CYCLES - 1);

endmodule