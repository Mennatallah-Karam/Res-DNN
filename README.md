# Res-DNN — End-to-End RNS-Based CNN Inference Accelerator

A SystemVerilog implementation of a full convolutional neural network inference
pipeline that performs **all arithmetic in the Residue Number System (RNS)**
instead of standard two's-complement binary. Convolution, bias-add, ReLU, and
max-pooling are all implemented as residue-domain operations across an 8-layer
AlexNet-style CNN, from the raw input image down to the final class logits.

## Why RNS?

In binary arithmetic, a wide adder or multiplier needs its carry to ripple
through every bit — the more bits, the longer the critical path. RNS avoids
this by representing every number as a small tuple of independent residues,
one per modulus, the same way a wide data bus can be split into independent
byte lanes: `x → (x mod m1, x mod m2, x mod m3)`. Addition, subtraction, and
multiplication can then be done **channel-by-channel in parallel**, with no
carry ever crossing between channels — much like three narrow, independent
pipelined FIR taps running side by side instead of one wide accumulator. This
suits CNN inference well, since a convolution is overwhelmingly
multiply-accumulate work that RNS turns into cheap, narrow, parallel modular
MACs. The cost is that operations that depend on magnitude — comparison,
sign, division — aren't free in RNS and need dedicated circuits; this project
implements exactly those (sign detection for ReLU, max-pooling) directly in
the residue domain, without ever converting back to binary mid-pipeline.

## Moduli set

This design uses the balanced 3-modulus set described in the project's
reference paper (see in-code comments citing "Section III-A", "Fig. 10/11"):

| Channel | Modulus | Value | Width |
|---|---|---|---|
| `x1` | `2^n − 1` | 31 | 5 bits |
| `x2` | `2^n`   | 32 | 5 bits |
| `x3` | `2^(n+1) − 1` | 63 | 6 bits |

with `n = 5`, giving a dynamic range `M = 31 × 32 × 63 = 62,496`
(`rns_pkg.sv`). The `x2` channel (modulus `2^n`, a trivial "free" channel in
binary) is the one that needs **base extension** before a multiply-accumulate
and **scaling** afterward, since it's the channel that can silently overflow
without the redundancy the two Mersenne-modulus channels provide.

## Network topology

`rns_alexnet_top.sv` instantiates a scaled-down, CIFAR-10-style AlexNet: a
32×32×3 input, 5 conv layers, and 3 fully-connected layers, ending in 10
class logits.

| # | Layer | C_in | Kernel | Channels | Output (H×W) | Pool | ReLU |
|---|---|---|---|---|---|---|---|
| 0 | conv1 | 3    | 3×3 | 64   | 32×32 → 16×16 | 2×2 | ✓ |
| 1 | conv2 | 64   | 3×3 | 192  | 16×16 → 8×8   | 2×2 | ✓ |
| 2 | conv3 | 192  | 3×3 | 384  | 8×8           | —   | ✓ |
| 3 | conv4 | 384  | 3×3 | 256  | 8×8           | —   | ✓ |
| 4 | conv5 | 256  | 3×3 | 256  | 8×8 → 4×4     | 2×2 | ✓ |
| 5 | fc1   | 4096 | 1×1 | 4096 | 1×1           | —   | ✓ |
| 6 | fc2   | 4096 | 1×1 | 4096 | 1×1           | —   | ✓ |
| 7 | fc3   | 4096 | 1×1 | 10   | 1×1           | —   | — (raw logits) |

Only `conv1` reads a raw binary (two's-complement) input image; every
subsequent layer consumes and produces RNS residues directly, so the
network never round-trips through binary internally — the residues for one
layer's pooled activations feed straight into the next layer's PE array.


## Pipeline (per layer)

```
                 ┌───────────────────────────────────────────────────────────┐
                 │                      rns_pe_top_chained                    │
                 │                                                           │
prev.  ─────────►│  ┌────────────┐   ┌───────────┐   ┌──────┐   ┌─────────┐  │──► pooled
activations      │  │  ifmap src │──►│  rns_pe_  │──►│ ReLU │──►│ MaxPool │  │    activations
(or file, conv1) │  │ (forward   │   │   unit    │   │(sign │   │ (residue│  │    (act_store)
                 │  │ converter  │   │  (RNS MAC)│   │detect)│  │ domain) │  │
                 │  │ for conv1) │   └───────────┘   └──────┘   └─────────┘  │
                 │  └────────────┘         ▲                                 │
                 │                    rns_pe_controller                      │
                 │                (address gen / MAC sequencing)             │
                 └───────────────────────────────────────────────────────────┘
```

Inside `rns_pe_unit` (the actual MAC datapath), each convolution output goes
through the following stages, in order.

**Ifmap source select.** `rns_forward_converter` (conv1 only) turns a signed
binary pixel into `(x1, x2, x3)`; later layers already have residues from the
previous layer's activation store.

**Base extension** (`rns_base_extension`, `E = K_MUL = 3`). Widens the `x2`
channel of both weight and ifmap by `K_MUL` bits via mixed-radix
reconstruction, so the power-of-two channel can't silently wrap during the
multiply-accumulate that follows.

**Channel-wise modular multiply** (`rns_channel_multiplier`). A Booth
radix-4 multiplier per channel, Mersenne-folded (mod `2^W−1`) for the
`x1`/`x3` channels or truncated (mod `2^W`) for `x2`.

**Accumulate** across all `C_in × kernel × kernel` taps of one output pixel,
entirely in the extended residue domain.

**Scale back down** (`rns_scaling_unit`, inverse of the base-extension step)
once the last tap lands.

**Bias add**, itself base-extended (`K_ADD = 6`) and re-scaled the same way,
so the bias never has to be decoded to binary either.

**ReLU** (`rns_relu_unit` + `rns_sign_detector` + `rns_partition_functions`).
The sign of a value is recovered from its three residues via a mixed-radix
comparison, and all three output residues are zeroed when negative. No
CRT/binary reconstruction is needed just to apply ReLU.

**Max-pooling** (`rns_maxpool_unit` + `rns_max_pool`). The same
residue-domain comparator used for ReLU's sign detection is reused to pick
the larger of two residue triples, streamed over each 2×2 (or 1×1, i.e.
pass-through) pooling window.

The `rns_eac_adder` (a Sklansky-tree, end-around-carry adder for mod
`2^W − 1` arithmetic) and `rns_compressor` (Wallace-style 4:2 reduction for
the Booth multiplier) are the shared low-level primitives everything above
is built from.


## Repository layout

```
rns_pkg.sv                    RNS parameter package (moduli, widths, residue struct)
rns_alexnet_top.sv            Top-level: 8 chained layers + layer sequencer FSM
rns_pe_top_chained.sv         One network layer, fed by the previous layer's activations
rns_pe_top.sv                 One network layer, fed by files (used by per-layer testbenches)
rns_pe_controller.sv          Per-layer address generator / MAC-sequencing FSM
rns_pe_unit.sv                The RNS MAC datapath (convert → extend → multiply → accumulate → scale → bias)
rns_conv_relu_pool_layer.sv   Wraps one PE with ReLU + max-pool + control-pipe alignment FIFOs
rns_pe_memories.sv/rns_mem_top.sv  $readmemh-backed weight/bias/ifmap memories
rns_forward_converter.sv      Binary (two's complement) → RNS residue triple
rns_base_extension.sv         RNS base extension (overflow-safe channel widening)
rns_scaling_unit.sv           Inverse of base extension (residue-domain scale-down)
rns_mod_reduce.sv             Small binary → residue reducer (helper for scaling)
rns_channel_multiplier.sv     Booth radix-4 modular multiplier (Mersenne fold / mod-2^W truncate)
rns_compressor.sv             Wallace-style N:2 compressor for the multiplier
rns_eac_adder.sv              Sklansky end-around-carry adder (mod 2^W − 1 add/sub primitive)
rns_sign_detector.sv          Recovers sign from a residue triple (drives ReLU)
rns_partition_functions.sv    Mixed-radix partition values used by the sign detector
rns_relu_unit.sv              ReLU applied directly on residues
rns_max_pool.sv/rns_maxpool_unit.sv  Residue-domain "keep the larger" comparator + window sequencer

rns_params_out/               Per-layer weights & biases, pre-converted to residues
                               (<layer>_weight_r{31,32,63}.mem/.txt, <layer>_bias_r{31,32,63}.mem/.txt)
sw_trace/mem/                 Golden reference activations from a software model, per layer
                               and per stage (conv-out, relu, pool), plus fc3_logits_true.txt
ifmap_bns.mem                 The single padded input image (3×34×34, signed 16-bit) for conv1

tb_alexnet_top.sv             Full end-to-end chain testbench (conv1 → fc3)
tb_conv1.sv … tb_conv5.sv     Per-layer conv testbenches
tb_fc1.sv … tb_fc3.sv         Per-layer FC testbenches
```

## Data file conventions

**`.mem` files** are `$readmemh`-formatted (one hex value per line) and are
read directly by the RTL memories at elaboration/runtime. Residue values are
stored at their natural channel width (5 bits for mod 31/32, 6 bits for mod
63); the raw conv1 ifmap is stored as signed 16-bit two's complement.

**`.txt` files** next to most `.mem` files are the human-readable equivalent
of the same data, useful for manually spot-checking a weight or bias value.

**`sw_trace/mem/`** holds a golden reference trace — the expected activation
residues after each layer's convolution, ReLU, and pooling stage — captured
from a software reference model, so RTL simulation output can be checked
stage-by-stage rather than only at the final output. `fc3_logits_true.txt`
is the ground-truth final logits for the one image encoded in
`ifmap_bns.mem`.

## Running the simulation

The RTL relies on SystemVerilog constructs (`always_ff`/`always_comb`,
packed structs, unpacked-array ports, `generate` blocks) and file I/O
(`$readmemh`/`$fopen`), so it needs an SV-capable event simulator —
ModelSim/Questa is what the testbenches were written for
(`tb_alexnet_top.sv` has the invocation in a header comment):

```tcl
vsim -c -do "run -all" tb_alexnet_top -l sim_output.log
```

Before running, update the DATA_PATH parameter (hardcoded in
`rns_alexnet_top.sv`'s default and in `tb_alexnet_top.sv`'s DATA_PATH
macro, currently set to `D-drive-style path full_ResDNN`) to wherever this
repository is checked out on your machine, since it's used to build the
absolute paths to `rns_params_out/*.mem` and `ifmap_bns.mem` at elaboration
time. The testbench also expects a writable `hw_out/` directory under
DATA_PATH for its output dump.

A sensible order to run things in: compile `rns_pkg.sv` first, since it's a
package other files import. Then run the single-layer testbenches
(`tb_conv1` … `tb_fc3`) individually to validate one layer's datapath against
its `sw_trace/mem` golden files before trusting the full chain. Next, run
`tb_alexnet_top` for the full conv1→fc3 pipeline — it prints a trace line as
each layer's activations land, and (since the FC layers carry 4096×4096
weight matrices) is guarded by a generous 500M-cycle watchdog so a stalled
chain fails loudly instead of hanging the simulator. Finally, on completion
the testbench writes the 10 fc3 logit residues to
`hw_out/alexnet_fc3_logits_r{31,32,63}.mem` — compare these against
`sw_trace/mem/fc3_logits_true.txt` to verify the hardware pipeline matches
the software reference.

## Current scope / known limitations

**Output stays in RNS form.** The network's final result is three residue
values per class logit; converting that back to a signed integer (or
computing an argmax) needs a CRT / mixed-radix decode that isn't included as
an RTL module yet — the only residue-to-magnitude operation implemented is
sign detection, used internally for ReLU.

**Simulation-only.** There's no XDC/constraints file or FPGA top-level
wrapper in the repo yet; as it stands this is a functional/behavioral
testbed for validating the RNS datapath in ModelSim/Questa, ahead of a
synthesis and on-board bring-up pass.

**Strictly sequential layers.** The top-level sequencer starts layer i+1
only after layer i's done signal fires — there's no cross-layer pipelining
or double-buffering of activations yet.

**DATA_PATH is a hardcoded absolute path** (and currently a Windows-style
one), so it must be edited per-machine before simulating, as noted above.
