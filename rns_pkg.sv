package rns_pkg;

  // ---- Base moduli-set parameters (Section III-A) ----
  parameter int N = 5;                 // n
  parameter int W1 = N;                // width of 2^n-1 channel   -> modulus 31
  parameter int W2 = N;                // width of 2^n channel     -> modulus 32
  parameter int W3 = N + 1;            // width of 2^(n+1)-1 channel -> modulus 63

  parameter int MOD1 = (1 << W1) - 1;  // 2^n - 1   = 31
  parameter int MOD2 = (1 << W2);      // 2^n       = 32
  parameter int MOD3 = (1 << W3) - 1;  // 2^(n+1)-1 = 63

  parameter int DYNAMIC_RANGE = MOD1 * MOD2 * MOD3; // 62,496 (paper: [0, 62496))

  // ---- Overflow-extension parameters (Fig. 10/11 in paper) ----
  parameter int K_MUL  = 3;
  parameter int KP_ADD = 6;

  // ---- Packed RNS residue triple ----
  // x1: mod (2^n - 1), width W1
  // x2: mod  2^n,       width W2  (this is the channel that gets extended)
  // x3: mod (2^(n+1)-1), width W3
  typedef struct packed {
    logic [W3-1:0] x3;
    logic [W2-1:0] x2;
    logic [W1-1:0] x1;
  } rns_word_t;

endpackage : rns_pkg