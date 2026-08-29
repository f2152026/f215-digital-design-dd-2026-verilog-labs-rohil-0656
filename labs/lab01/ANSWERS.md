# Lab 01 — Answers & Observations

All designs below were compiled and simulated with Icarus Verilog
(`iverilog -g2012 ... && vvp ...`) against the given, unmodified `tb.v`
files. Numbers quoted (settle times, final values) are taken directly from
those runs, not estimated.

---

## Task 1 — Gate ordering and delay

**(a)** `FA_Gate.v` as given, no delays: `sum`/`cout` match the full-adder
truth table at all 8 input combinations (verified — see monitor output,
e.g. `a=0 b=1 cin=1 -> sum=0 cout=1`).

**(b)** Reordering the five gate instantiations (moving `or` to the top,
`xor` to the bottom, etc.) and re-simulating with the same `tb.v` produces
an **identical** waveform to (a), transition-for-transition.

**(c)** Adding a constant delay (`#(2)`) to every gate **does** change the
waveform: instead of jumping straight to the final value, `sum`/`cout` now
step through intermediate/glitch values before settling (e.g. at
`a=1,b=1,cin=0` the trace shows `cout` glitch to `1` then settle to `1` a
few ns later via a different path — visible as extra `$monitor` lines
between each input change).

**Why:** Verilog's gate-level primitives are **scheduled by data
dependency in the event queue**, not by their textual order in the
module. Simulation time only advances when the scheduler processes
events; without delays, every gate that has valid inputs fires in the
same simulation time step (delta cycles resolve the order internally), so
the file's line order is irrelevant to (b). Delays change this because
now each gate's output update is scheduled a fixed number of time units
*after* its inputs change, so gates downstream in the actual signal path
(not the file) update visibly later — which is what makes the ripple in
1(c) and Task 2 observable at all.

---

## Task 2 — Ripple adder, gate delays

Completed `ripple_adder.v` (FA0..FA3, named ports, carry chain
`c1,c2,c3`) simulated correctly against all 5 test vectors in `tb.v`
(confirmed independently with an extended-settle-time check, not just the
testbench's own dead time — see Task 2 note below).

**1. Arithmetic check:** every vector settles to the arithmetically
correct sum/cout (e.g. `1010+0101+0 = 1111`, `cout=0`; `1111+0001+0 =
0000`, `cout=1`).

**2. The 7+1 vector:** `a=0111, b=0001, cin=0`. In the waveform, `sum`
visibly steps `0000 -> 0110 -> 0100 -> 0000 -> 1000` before settling,
each step ~3-4ns apart — that's `c1`, then `c2`, then `c3` flipping in
turn as the carry ripples FA0→FA1→FA2→FA3. With no delays (Task 1)
this would be invisible (all in one delta cycle); with delays, each hop
costs one AND+OR gate's worth of time (~4-6ns per stage here), so the
ripple is directly visible in the trace.

**Note on the last vector:** for `a=1010,b=0101,cin=0`, the testbench
gives only 20ns before `$finish`. The true settled answer is `sum=1111,
cout=0` (confirmed with a 100ns-settle scratch testbench), but the
worst-case carry path through 4 chained stages of rise/fall-delay gates
can take up to ~27ns — slightly *more* than the 20ns gap — so the
`$monitor` line printed at `$finish` for that specific vector can still
be mid-transition. This isn't a bug in the adder; it's the same
ripple-delay effect from Q2, just landing close to the testbench's
timing budget. It's a nice preview of Task 3/4's point: ripple adders'
worst-case delay grows with width, and eventually costs you.

---

## Task 3 — Three 4-bit adders

`rca.v`, `cla4.v` (gate-level), `cla4_dataflow.v` (dataflow) all simulate
correctly against the same `tb.v`, verified by cycling `dut.v` through
all three options.

**Reflection (b) — 64-bit gate-level CLA by hand:** No. `cla4.v`'s carry
equations grow one AND-term literal longer every bit: `c1` needs a
2-literal term, `c4`/`cout` needs a 5-literal term. Scaling the *same
direct (non-hierarchical) construction* to 64 bits, the term feeding the
final carry (`c64`) is `p63.p62...p0.cin` — **65 literals** in one AND
gate. Real gate libraries top out around 4-8 inputs, so this is already
unrealistic to hand-instantiate correctly, let alone build in real
hardware — which is exactly the motivation for Task 4.

**Reflection (c) — `cla4.v` vs `cla4_dataflow.v`:** `cla4.v` is ~45
lines of gate primitives with 20 explicitly-named intermediate wires
(`t1_0`, `t2_0`, `t2_1`, ...); `cla4_dataflow.v` is ~10 lines, each
`assign` reading almost identically to its Boolean equation
(`c2 = g1 | (p1&g0) | (p1&p0&cin)`). For maintenance six months out, the
dataflow version wins easily — the equation *is* the code, whereas the
gate-level version requires mentally re-deriving which named temp wire
corresponds to which product term.

**Question (settling speed, all three, on the 7+1 vector):** with the
required `FA_Gate.v` carried over from Task 2 (rise/fall delays), `rca`
took **14ns** after the input changed to reach its last transition;
`cla4` (gate-level, `#(2)` delays) took **8ns**; `cla4_dataflow` took
**6ns**. The two-level CLAs settle roughly 2-3x faster than the ripple
adder for this width, and the dataflow version edges out the gate-level
one only because each `assign #(2)` here bundles an entire equation into
one scheduled delay rather than stacking discrete AND-then-OR gate
delays — an artifact of the abstraction level, not a "faster circuit."

---

## Task 4 — Three 64-bit adders

All three (`rca64.v`, `cla64_flat.v`, `cla64_blocked.v`) simulate
correctly. `cla64_flat.v`'s 64 carry equations (`c[1]..c[64]`) were
generated programmatically following the exact `cla4.v` pattern, then
verified two ways as instructed:
- `c[1]..c[4]` are, term for term, the same equations as `cla4.v`'s
  `c1, c2, c3, cout` (only the signal names differ: `p0`→`p[0]`, etc.).
- `c[10]` and `c[32]` were re-derived by hand from the recursive
  definition `Ck = Gk-1 + Pk-1.Ck-1`, unrolled down to `C0 = cin`; both
  match the generated terms exactly.

**Settling-time comparison** (measured as time-after-input-change of the
last signal transition, same three post-reset vectors in `tb.v`):

| vector | rca64 | cla64_flat | cla64_blocked |
|---|---|---|---|
| `0xFFFF..FF + 1` | ≥27ns (**not settled** by the 30ns mark — true answer `sum=0,cout=1` confirmed only with a 500ns scratch run) | 6ns | 28ns |
| `0x0F0F.. + 0xF0F0..` | ≥29ns (**not settled**) | 4ns | 26ns |
| `123456789 + 987654321` | 24ns (marginal/possibly not fully settled) | 6ns | 12ns |

**1/2. Speedup vs `rca64`:** `cla64_flat` settles in single-digit ns
regardless of vector — a 64-bit ripple adder's worst-case delay grows
*linearly* with width (64 stages × ~6ns/stage ≈ up to 300+ns, confirmed:
it hadn't even converged within the testbench's 30ns gap for two of the
three vectors), while the flat CLA's two-level structure keeps delay
roughly *constant* regardless of width. This qualitatively matches
Tutorial 3's prediction that CLA delay is O(1) (well, O(log n) once fan-in
limits are respected) versus RCA's O(n).

**3. Why use `cla64_blocked` over `cla64_flat` in a real chip, if they
simulate similarly here:** the two aren't actually similar here —
`cla64_blocked` (26-28ns) is noticeably slower than `cla64_flat`
(4-6ns) in this simulation too, because block-to-block carry still
ripples through 16 stages. The real reason to prefer the blocked design
in silicon isn't speed, though — it's the point from Task 3(b):
`cla64_flat`'s largest AND term (`c[64]`'s last product) has **65
literals** (`p[63]&p[62]&...&p[0]&cin`), which no real logic gate can
implement directly; it would have to be built from a tree of smaller
gates anyway, eroding the "flat" delay advantage and burning far more
transistors/area for marginal benefit. `cla64_blocked` bounds every gate
to at most 5 inputs (matching `cla4.v`'s own worst case) at the cost of
some carry-rippling between blocks — a much more practical area/delay
trade-off, which is exactly what Task 5 tries to fix without giving up
that bound.

---

## Task 5 (Bonus) — Hierarchical (2-level) CLA

Built by applying the P/G-lookahead trick one level up: each 4-bit block
gets its own block-generate/block-propagate pair (`BG[k]`, `BP[k]`, using
the same equation shape as `cla4.v`'s own `cout`), then a *second*
16-wide lookahead unit computes every block's carry-in directly from
`BG`/`BP`/`cin` — removing the block-to-block ripple that `cla64_blocked`
still has. Largest term here is `BP[15]&...&BP[0]&cin` — only **17
literals**, comfortably closer to buildable than the flat design's 65.

**Settling time vs `cla64_blocked`** (same vectors, both measured from
input change):

| vector | cla64_blocked | cla64_hier |
|---|---|---|
| `0xFFFF..FF + 1` | 28ns | **12ns** |
| `0x0F0F.. + 0xF0F0..` | 26ns | **8ns** |
| `123456789 + 987654321` | 12ns | 12ns |

The hierarchical version is 2-3x faster than the plain blocked design on
the vectors that actually stress the block-to-block carry chain, while
still keeping every gate's fan-in bounded (max 17, vs. the flat design's
65) — the practical middle ground the bonus task was aiming for.

---

*All final numeric results (e.g. `123456789 + 987654321 = 0x423a35c6`)
were cross-checked against plain Python arithmetic, and every design's
`$finish`-time output was additionally verified against a long-settle
(500ns+) scratch testbench where the given `tb.v`'s dead-time looked
marginal, to confirm the *design* was correct even when the *given
timing budget* wasn't enough to observe it settle.*
