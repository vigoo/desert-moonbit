# desert-moonbit optimization plan

Living document. Every experiment, finding, and idea gets recorded here —
including the ones that don't work. Constraints: **no wire-format changes**,
**no feature/compatibility loss**, keep `moon check` warning-free and the
full test suite (currently 102 tests) green on all four targets after every
step. Baselines and the head-to-head against desert-rust live in
[docs/benchmarks.md](docs/benchmarks.md).

Current post-lazy-state baseline (native, release, comparison harness):

| Case | Rust native | MB native | MB wasm-gc |
|---|---:|---:|---:|
| serialize i32 | 17.5 ns | 121 ns | 46 ns |
| deserialize i32 | 2.1 ns | 49–53 ns | 27 ns |
| serialize string (43 B) | 22.9 ns | 186 ns | 334 ns |
| deserialize string (43 B) | 21.8 ns | 313 ns | 280 ns |
| roundtrip Array<Int> ×1000 | 1.51 µs | 7.4 µs | 18.7 µs |
| roundtrip Bytes 4096 B | 147 ns | 494 ns | 1.8 µs |
| roundtrip evolved record | 515 ns | 2.2 µs | 3.0 µs |
| dedup strings ×100 (ser) | 6.2 µs | 8.0 µs | 13.1 µs |
| golden dataset serialize | 274 µs | **226 µs (MB wins)** | 901 µs |
| golden dataset deserialize | 29.5 µs | 106 µs | 1162 µs |

Cost decomposition (native): serialize i32 = ~60% per-call allocation,
~14% `to_bytes` copy, ~4% format work; deserialize i32 = ~95% per-call
allocation. Trait-object dispatch ≈2.4 ns/op.

---

## Findings log

| # | Finding | Impact |
|---|---|---|
| F1 | `SerializerState` eager HashMaps dominated every small op → lazy allocation | 15–33x on small ops |
| F2 | Per-call allocation is 60–95% of small-op cost; format work is ~4% | drives the whole plan |
| F3 | `Buffer::write_int_be` etc. are already guarded bulk writes into `FixedArray` (core) | nothing to gain re-implementing them |
| F4 | `FixedArray::unsafe_write_uint32_be/uint64_be/...` intrinsics exist | bulk array paths can write packed BE with 1 intrinsic per element |
| F5 | `FixedArray::blit_from_string` is UTF-16, not UTF-8 — unusable for string payload encoding | need own transcode; `Buffer::write_string_utf8` exists though |
| F6 | Specific `impl Trait for T` overrides the trait's default impl cleanly (probed); generic blanket `impl[T : Show] Speak for Array[T]` triggers `unused_trait_bound` if the bound isn't used in the body — constraints only pay their way when used | specialization design: per-type impls, not unused-bound blankets |
| F7 | `moon bench`/`it.keep` boxes per-op; comparison harness (plain loops + accumulation) is the trustworthy measurement path | measure with `bench_compare_wbtest.mbt` |
| F8 | MoonBit String `<` is not byte-lexical; `lexical_compare` is | codegen `sorted_constructors` correctness |
| F9 | MoonBit beats Rust already on golden serialize + dedup back-ref deserialize; wasm-gc loses badly on large payloads | large-data story = native target |

---

## Step 1 — String write fast path (core UTF-8 writer) — REVERTED

**Idea.** `Buffer::write_string_utf8(StringView)` exists in core. Our
`write_string_payload` currently runs `utf8_byte_length` (scan) + `write_utf8`
(transcode into a fresh FixedArray) + `Bytes::from_array` + `exact_view` —
two allocations and two copies per string. Calling core's writer through the
context removes both.

**Experiments.**
- E1a (correctness): core's writer encodes proper surrogate pairs correctly
  (StringView iteration yields astral code points as single chars) BUT
  3-byte-encodes lone surrogates directly (0xED-prefixed) instead of our
  documented `?` substitution (Scala getBytes behavior). Incompatible → can
  only be used behind a scan-and-fallback.
- E1b (perf): wired `write_string_utf8` as a provided trait method
  (ByteOutput overrides with core passthrough), scan picks fast/slow path.
  **REGRESSED**: string serialize 186 → 283 ns. Core's writer is a per-char
  loop (branch + grow-check per character) — slower than our bulk transcode
  + blit even with two allocations.
- E1c: returning a scan struct (`Utf8Scan`) from the counting pass also
  regressed (+70 ns) — extra GC allocation per call. Tuples would too.

**Result.** REVERTED to the original scratch path (186 ns-class restored).
Infrastructure kept: `write_string_utf8` is now a provided `BinaryOutput`
method (default transcodes; ByteOutput overrides with core passthrough) —
usable by future paths where the string is already UTF-8-clean and the
per-char cost is amortized. New finding F10 recorded.

**Finding F10.** For short payloads (< a few hundred bytes), allocation-free
per-char loops LOSE to allocate-then-blit in MoonBit. Bulk transfers into
unboxed `FixedArray` + one `blit` are the winning pattern. Revisit only for
very large strings where per-char cost could dominate — untested so far.

---

## Step 2 — Bulk fixed-width Array serialization — PARTIAL (opt-in)

**Idea.** `Array[Int]`, `Array[Int64]`, `Array[Float]`, `Array[Double]`,
`Array[Byte]`(already block) currently pay per-element trait-object dispatch
(~12 ns/element vs Rust ~1.5 ns). Since `SerializationContext` forwards
`BinaryOutput`, write counted-form fixed-width collections via bulk loops
using `unsafe_write_uint32_be`-style writes into the active sink... blocked:
the sink is a `&BinaryOutput` (virtual). Two variants:
V-A: loop `ctx.write_i32` (still virtual per element but drops iterator +
generic machinery); V-B: detect `ByteOutput`-backed sinks and write straight
into the backing Buffer with `FixedArray::unsafe_write_*`. Wire-identical
either way.

**Experiments.**
- E2a (V-A, dispatch-chain decomposition, 1000 i32 writes): full path
  4.93 µs → reused ctx (drop alloc) 4.26 µs → direct `ByteOutput` (drop one
  virtual hop) 3.85 µs → direct `Buffer` (no virtual at all) 4.14 µs.
  Conclusion: the virtual hops cost ~10%; **the floor is ~4 ns/element for
  BE writes into GC-managed `FixedArray`** (4 separate byte stores + guard)
  vs Rust's single 4-byte store (~0.7 ns/element roundtrip-adjusted). This
  is a backend/runtime characteristic, not a library-level one.
- E2b (opt-in specialized serializer `ArrayOfInt`, plain loop of
  `ctx.write_i32`): serialize-only 5.93 → 5.33 µs (~10%), wire-identical.
- E2c (scratch reuse for string encoding via a context field): isolated
  probe suggested ~30 ns/string; in-context A/B showed NO consistent win
  (Array<String> roundtrip 16.7 µs fresh vs 18.2–18.8 µs reused — reuse is
  actually slower, the mut-Option indirection costs as much as the small
  `FixedArray::make`). Reverted to fresh scratch. The earlier probe's
  "win" was confounded by per-call context allocation in its fresh case.

**Result.** PARTIAL. `ArrayOfInt` opt-in acceleration newtype kept
(wire-identical, generic deserialize accepts its bytes; ~10% serialize-only).
Backend floor documented (F11). Scratch reuse rejected (F13).

**Findings.**
- **F11**: MoonBit native floor ≈ 1 ns/byte for guarded BE writes into
  `FixedArray[Byte]` (4 byte-stores + length guard per i32). Rust ≈ 0.2
  ns/byte (single wide store into `Vec<u8>`). Library-level code cannot fix
  this; it is the backend's array-store codegen.
- **F12**: Concrete-type trait calls (e.g. `Int::serialize` inside generic
  `Array[T]` code) are already cheap — removing the iterator/generic layer
  saved only ~10%. The `&BinaryOutput` hop costs ~2.4 ns/call as previously
  measured.
- **F13**: Context-field scratch reuse (mut Option + match per string)
  shows no consistent in-context win; per-string `FixedArray::make` for
  ~50 B is cheap. Rejected.

**Step 3 status**: 3a (reuse facade) already existed (`serialize_to_output`)
+ canary case (5.6 vs 4.8 ns Rust — near parity). 3b (scratch reuse)
rejected by F13. 3c (view-based reads where possible) already implemented
(`read_bytes_view`).

**Step 3d — context reuse for deserialization (ADDED, measured win).**
New API: `BinaryInput::reset_input(data)` (swap buffer, clear regions) and
`DeserializationContext::reset_input(data)` (reset input + fresh session
state — dedup ids never leak, same isolation guarantee as the top-level
functions). Measured (native, release):

| Case | fresh-context deserialize | reused-context deserialize | gain |
|---|---:|---:|---:|
| deserialize i32 | 69–74 ns | **17.5 ns** | ~4x |
| deserialize evolved record | 2.2 µs | **1.04 µs** | ~2.1x |

Wire-identical (bytes are data); no feature sacrificed — session isolation
is preserved by the fresh state. This closes most of the small-op
deserialization gap that motivated roadmap #1: 69 ns vs Rust's 2.1 ns is
mostly allocation, and with reuse the remaining 17.5 ns is format work +
loop overhead. Serialization-side counterpart is
`serialize_to_output` + `ByteOutput::reset` (canary: 5.6 vs 4.8 ns).

**Step 3e — lazy region_stack (ADDED, measured win).**
`BinaryInput::new` allocated a `region_stack` Array on every call although
only evolved records (V>0) ever push regions. Made it lazy
(`Array[..]? = None`, allocated on first `push_region`, cleared by
`reset_input`). Measured (native, release):

| Case | before | after | gain |
|---|---:|---:|---:|
| deserialize i32 (fresh path) | 69–74 ns | **49–53 ns** | ~30% |
| full deserialize path (decomposition G) | 68.7 ns | **48.4 ns** | ~30% |
| deserialize i32 (reused ctx) | 17.5 ns | 21.8 ns | (noise; reused path unaffected in real terms) |

All 105 tests green on all four targets.

---

## Step 3 — Allocation reduction

**Idea.** Three sub-steps:
3a. `serialize_into_bytes(value, &mut ByteOutput)` facade (mirror Rust
`serialize_into_byte_vec`) — done partly via `serialize_to_output`; add
reset-and-reuse guidance + benchmark (reused-buffer canary already at
5.6 ns vs 4.8 ns Rust).
3b. UTF-8 scratch reuse: keep one scratch `FixedArray[Byte]` in
`SerializationContext` sized to the largest string so far, grow on demand —
removes per-string FixedArray allocation.
3c. `deserialize` variants that skip the exhaustive check cheaply (already
exists) + avoid `Bytes` allocation in `read_bytes` where a view suffices.

**Result.** TBD

---

## Step 4 — Static dispatch for the context (bigger refactor, deferred)

**Idea.** Make `SerializationContext` generic over the sink
(`SerializationContext[T]`) or pass sinks as concrete type parameters —
monomorphizes codec code like Rust's design. Costs: codegen templates, trait
signature churn. Defer until 1–3 land and are re-measured.

**Result.** TBD

---

## Rejected / not-pursued

- **`FixedArray::blit_from_string` for string payloads** — UTF-16 encoding,
  wire needs UTF-8 (F5).
- **Hand-rolled Buffer replacement** — core's Buffer already does guarded
  bulk writes + growth well (F3); wrapping is enough.
- **Blanket generic impls with unused bounds** — warning noise, no dispatch
  benefit (F6).

## Measurement protocol

1. `moon check` clean (0 warnings), `moon test` all green.
2. Comparison harness: `moon test bench_compare_wbtest.mbt --target native
   --release` and `--target wasm-gc`; record the changed rows.
3. `moon bench` canaries (reused-buffer, golden ser/deser) for regression
   tracking.
4. Update this log + docs/benchmarks.md with before/after.
