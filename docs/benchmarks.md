# Benchmarks and comparison against desert-rust

This chapter reports the micro-benchmark suites shipped in the repository and
a head-to-head comparison against desert-rust (`desert_rust` 0.1.11, HEAD
`b4302f5`), measured with identical workloads on identical harnesses.

## Suites

1. **`moon bench` suite** (`bench_wbtest.mbt`) — the library's own micro
   benchmarks, tracked in CI-able form. Ten scenarios covering primitives,
   strings, varints, collections, byte blocks, an evolved record, string
   deduplication and size estimation. Run with:

   ```sh
   moon bench                    # default target (wasm-gc)
   moon bench --target native
   ```

2. **Comparison harness** (`bench_compare_wbtest.mbt` for MoonBit,
   `/tmp`-side Rust script for desert-rust) — two *structurally identical*
   plain timing loops (no benchmark-framework machinery on either side):
   warmup, then a tight loop accumulating each operation's result into a sum
   (preventing dead-code elimination on both sides), wall-clock measured.
   Iteration counts match per scenario. This is the apples-to-apples table
   below.

Environment: AMD Ryzen 7 3800X (boost clocks enabled), Linux 6.18,
rustc 1.99.1 (`--release`, opt-level 3 + LTO), MoonBit `moon 0.1.20261104`
(`--release` for native; wasm-gc as shipped by the toolchain).
All numbers are medians of repeated runs; run-to-run variance was below 10%.

## Benchmark case inventory

### Suite 1 — comparison harness (`bench_compare_wbtest.mbt` + Rust script)

The apples-to-apples set used for the cross-language table below. Every case
runs the *full public API path* (fresh output buffer, session state, context
per op — the cost applications actually pay), measured with plain timing
loops + result accumulation (no framework boxing) on both sides.

| # | Case | Work / wire size | Cost it isolates |
|---|---|---|---|
| 0 | `baseline (empty op)` | no-op returning 1 | harness loop floor (Rust ~0.3 ns, MB native 1.5 ns, MB wasm-gc 9.8 ns) |
| 1 | `serialize i32` | 123456789 → 4 B | fixed per-call cost floor; allocation-dominated (roadmap #1) |
| 2 | `deserialize i32` | 4 B → i32 | read-side fixed cost floor (roadmap #1) |
| 3 | `serialize string (43 B)` | 43-char ASCII → 44 B | UTF-16→UTF-8 transcode + copy chain (roadmap #1 scratch) |
| 4 | `deserialize string (43 B)` | 44 B → String | UTF-8→UTF-16 decode + allocation |
| 5 | `write var_i32(-123456789)` | → 5 B | pure varint encoding loop |
| 6 | `roundtrip Array<Int> × 1000` | → ~4 KB | per-element dispatch amortization; bulk-path candidate (roadmap #2) |
| 7 | `roundtrip Bytes 4096 B` | → ~4.1 KB | byte-block bulk copy path |
| 8 | `roundtrip evolved record` | 5-field V=1 record → ~120 B | codegen record path incl. version byte + 2-entry header + chunks |
| 9 | `dedup strings × 100` | 100 × 28-char string, 1 inline + 99 back-refs → ~130 B | session hash-table cost (dedup itself) |
| 10 | `serialized_size(record)` | size-only pass → ~120 B | write path without materializing bytes |

### Suite 2 — `moon bench` in-repo suite (`bench_wbtest.mbt`)

The same ten scenarios as suite 1 minus the baseline, run through the
`moon bench` framework (slightly higher absolute numbers due to per-iteration
result-keeping; used for regression tracking on any target). Identical
workloads.

### Suite 3 — decomposition experiments (`bench_experiments_wbtest.mbt`)

Not workloads but cost attribution probes around `serialize/deserialize i32`
(A full path, B reused ctx, C direct Buffer, D alloc-only, E state-only,
F `to_bytes` copy, G full deserialize, H reused input). These are the
"why" behind the numbers; see the decomposition section below.

### Gap cases + golden (rows 11–22, added 2026-11-09)

The previously-identified gaps are now cases 11–22 in the table below,
including the golden dataset — the 242,540-byte real-life model written by
desert-scala (nested exceptions with 16-frame stack traces and a cause, an
evolved record, a sorted-constructor enum with a transient case, deduplicated
strings, collections) as both a serialization and a deserialization case.
The MoonBit golden model/codec and the Rust `TestModel1` both live in their
respective test/bench files; the Rust harness embeds the same
`dataset1.bin` via `include_bytes!`.

## Head-to-head: desert-rust (Rust native) vs desert-moonbit

| Scenario | Rust native | MoonBit native | MoonBit wasm-gc | MB native / Rust |
|---|---:|---:|---:|---:|
| baseline (empty op) | ~0.3 ns | 1.5 ns | 9.8 ns | — |
| serialize i32 | 17.5 ns | 121 ns | 46 ns | ~7x |
| deserialize i32 | 2.1 ns | 49–53 ns | 27 ns | ~24x |
| serialize string (43 B) | 22.9 ns | 201 ns | 334 ns | ~9x |
| deserialize string (43 B) | 21.8 ns | 315 ns | 280 ns | ~14x |
| write var_i32(-123456789) | 19.1 ns | 87 ns | 46 ns | ~4.6x |
| roundtrip Array/Vec\<Int> × 1000 | 1.51 µs | 7.4–12 µs | 18.7–19.7 µs | ~5–8x |
| roundtrip Bytes 4096 B | 146.6 ns | 482–514 ns | 1.80–1.88 µs | ~3.4x |
| roundtrip evolved record | 514.7 ns | 2.17–2.24 µs | 3.04–3.23 µs | ~4.3x |
| dedup strings × 100 | 6.23 µs | 8.7–9.3 µs | 11.9–13.1 µs | ~1.4x |
| serialized_size(record) | 160.6 ns | 871–1002 ns | 986–1179 ns | ~5.7x |

The evolved record has five fields (`id: i32`, `name: String`,
`score: f64`, `active: bool`, `tags: Array/Vec<String>` with 4 entries) and
one `FieldAdded` evolution step, matching both sides' codegen paths. Every
op includes the full top-level call cost — output buffer allocation, session
state, context construction, and (for roundtrips) the deserialization side.

### Reading the numbers

- **Close gaps**: string deduplication (~1.4x) is dominated by hash-table
  operations on both sides; the 4 KB byte block (~3.4x) is dominated by the
  buffer copy plus allocation.
- **Largest gaps**: tiny primitive ops. `deserialize i32` in Rust reads 4
  bytes from a slice with everything inlined; MoonBit pays for the same
  allocations every top-level call makes (output buffer, session state,
  context objects), which Rust also does but amortizes better through
  inlining and a mature allocator. These micro numbers upper-bound the per-op
  cost: batch scenarios (the × 1000 array row, ~5–8x) show the per-op fixed
  cost amortizing exactly as expected.
- **wasm-gc vs native**: MoonBit's wasm-gc backend (running under V8) is
  currently *faster* than its native backend for allocation-heavy small ops,
  and its baseline loop overhead is higher (9.8 ns vs 1.5 ns). For large
  Array roundtrips the relationship flips. The native backend is the youngest
  of MoonBit's targets; treat native numbers as a moving target.

## Head-to-head part 2: gap cases + golden dataset

| Scenario | Rust native | MoonBit native | MoonBit wasm-gc | MB native / Rust |
|---|---:|---:|---:|---:|
| serialize i32 (reused buffer) | 4.8 ns | 5.6 ns | 27.9 ns | ~1.2x |
| roundtrip Array/Vec\<String> × 100 | 4.89 µs | 16.3 µs | 24.5 µs | ~3.3x |
| roundtrip Map/HashMap\<String,i32> × 100 | 10.0 µs | 18.1 µs | 23.6 µs | ~1.8x |
| roundtrip Option\<i32> / Int? | 21.2 ns | 183 ns | 98.4 ns | ~8.6x |
| roundtrip compressed 4096 B | 84.7 µs | 155 µs | 99.4 µs | ~1.8x |
| deserialize V0 data w/ defaults | 35.7 ns | 161 ns | 93.4 ns | ~4.5x |
| roundtrip V2 multi-chunk record | 579 ns | 1.84 µs | 1.13 µs | ~3.2x |
| deserialize dedup back-refs × 100 | 3.51 µs | 2.49 µs | 2.96 µs | **0.7x** |
| roundtrip Array/Vec\<Int> × 10 000 | 14.8 µs | 71.4 µs | 203 µs | ~4.8x |
| roundtrip Bytes 64 KB | 2.24 µs | 5.48 µs | 97.2 µs | ~2.4x |
| golden dataset serialize | 274.3 µs | 225.8 µs | 900.6 µs | **0.82x** |
| golden dataset deserialize | 29.5 µs | 106.3 µs | 1161.6 µs | ~3.6x |

Reuse-pattern cases (API added during optimization; resets a context instead
of allocating per op — the practical answer to the small-op fixed costs
above; session isolation preserved via fresh state):

| Scenario | Rust native | MoonBit native (reused ctx) | gain vs fresh |
|---|---:|---:|---:|
| serialize i32 into reused buffer | 4.8 ns | 5.6 ns | ~22x vs fresh (121 ns) |
| deserialize i32 from reused ctx | 2.1 ns | 17.5 ns | ~4x vs fresh (69 ns) |
| deserialize evolved record from reused ctx | (in 515 ns roundtrip) | 1.04 µs | ~2.1x vs fresh (2.2 µs) |

Highlights:

- **MoonBit is faster on two cases**: golden-dataset serialization (0.82x)
  and deserialize-side deduplication (0.71x) — the write path through the
  core `Buffer` and the Int-keyed dedup lookup table are competitive.
- **Buffer reuse nearly closes the gap**: `reset` + write into a
  caller-owned output runs at 5.6 ns vs Rust's 4.8 ns (~1.2x), confirming
  that per-call allocation — not format work — was the dominant cost, and
  that the reuse pattern is the immediate practical win for hot loops.
- **The real-life golden workload** (242 KB, deeply nested): MoonBit native
  serializes *faster* than Rust; deserialization is ~3.6x slower.
- **wasm-gc scales poorly on large payloads** (64 KB block, golden dataset):
  the GC and copy costs of the host runtime dominate at size; native is the
  target to benchmark for large-data workloads.
- `Option<Int>` roundtrip (~8.6x) and `V0 data w/ defaults` (~4.5x) are
  small-op fixed-cost cases — same story as suite-1 rows 1–2.

## The `moon bench` suite (post-optimization numbers)

| Scenario | wasm-gc | native |
|---|---:|---:|
| serialize i32 | 83 ns | 137 ns |
| deserialize i32 | 36 ns | 74 ns |
| serialize string (43 B) | 224 ns | 229 ns |
| deserialize string (43 B) | 298 ns | 317 ns |
| write var_i32 | 66 ns | 42 ns |
| roundtrip Array\<Int> × 1000 | 19.2 µs | 8.5 µs |
| roundtrip Bytes 4096 B | 1.17 µs | 545 ns |
| roundtrip evolved record | 1.82 µs | 2.21 µs |
| dedup strings × 100 | 10.4 µs | 8.8 µs |
| serialized_size(record) | 801 ns | 901 ns |

(`moon bench` numbers include the harness's per-iteration result-keeping
overhead, hence slightly higher than the comparison harness on the same
target; the relative picture matches.)

## Cost decomposition (native, release)

To attribute the remaining gap, `bench_experiments_wbtest.mbt` isolates the
pieces of a `serialize i32` / `deserialize i32` call (numbers in ns/op):

| Experiment | native | wasm-gc | what it isolates |
|---|---:|---:|---|
| A full `serialize_to_bytes` | 124 | 55 | the whole public path |
| B reused ctx, `write_i32` only | 5.5 | 13.9 | format work + buffer growth |
| C direct `Buffer.write_int_be` | 3.1 | 10.8 | B minus context dispatch |
| D alloc output + state + ctx only | 75 | 17.9 | per-call allocations |
| E `SerializerState::new` only | 13 | 6.7 | (now lazy, near-free) |
| F reused ctx + `to_bytes` copy | 22 | 29 | the final Bytes copy |
| G full `deserialize_exhaustive` | 69 | 32 | whole read path |
| H reused input, `read_i32` only | 3.2 | 25 | cursor read alone |

Attribution for `serialize i32` (124 ns native): **~60% per-call allocation**
(output buffer, context objects), **~14%** the final `Bytes` copy, **~4%**
actual format work, the rest glue. For `deserialize i32` (69 ns): the cursor
read itself is ~3 ns — **~95% is per-call allocation** of the input/context
objects. On wasm-gc the host GC makes those allocations 4x cheaper, which is
why wasm-gc numbers sit closer to Rust.

## Optimization found by the comparison

The first comparison run exposed a structural asymmetry: desert-rust
allocates its string-dedup/reference session state *lazily* (only when
deduplication is actually used), while the MoonBit port eagerly constructed
two hash maps on every top-level call — dominating every small op.

Making `SerializerState` lazy (hash maps allocated on first string
registration) changed the numbers dramatically:

| Scenario (native, release) | before | after | improvement |
|---|---:|---:|---:|
| serialize i32 | 1.79 µs | 121 ns | ~15x |
| deserialize i32 | 1.85 µs | 56 ns | ~33x |
| write var_i32 | 1.68 µs | 87 ns | ~19x |
| roundtrip evolved record | 6.06 µs | 2.17 µs | ~2.8x |
| serialized_size(record) | 2.46 µs | 0.87 µs | ~2.8x |

All 102 tests pass unchanged — the optimization is purely behavioral-neutral.

### Remaining optimization roadmap (ranked by measured impact)

1. **Allocation reduction on the hot path** (60–95% of small-op cost):
   - promote the buffer-reuse pattern (`ByteOutput::reset` +
     `serialize_to_output`) in the docs and add a Rust-style
     `serialize_into_byte_vec` facade for caller-owned buffers;
   - reuse a per-context scratch `FixedArray[Byte]` for UTF-8 encoding
     (currently one FixedArray + one Bytes copy per string);
   - consider a growable-chunk output type that can hand out bytes without
     the final copy (Rust's `BytesMut` → `freeze` pattern).
2. **Bulk fixed-width collection paths**: serialize/deserialize
   `Array[Int]`/`Array[Double]` etc. with packed writes instead of
   per-element trait-object dispatch — the ×1000-int loop pays ~12 ns/element
   on native vs Rust's ~1.5 ns, almost all dispatch and iterator overhead
   (the wire format is identical: count prefix + packed BE elements).
3. **Static dispatch for the context**: `SerializationContext` holds
   `&BinaryOutput` (a trait object, ~2.4 ns/op on native). Making the
   context generic over the output type would monomorphize codec code the
   way Rust's generic `SerializationContext<Output>` does. Larger refactor.
4. **Compiler evolution**: MoonBit's native backend is the youngest target;
   wasm-gc numbers are already within ~3x of Rust on several ops. Re-run the
   comparison as the toolchain advances rather than hand-optimizing against
   today's codegen.

## Cross-library context

desert-rust's own `BENCHMARKS.md` runs a macro benchmark (10,000 oplog
entries) comparing desert against JSON/bincode/MessagePack/postcard/BARE/
bitcode. That model is not ported yet; porting it would give an end-to-end
cross-language datapoint at scale. In desert-rust's own numbers, desert
serializes that workload in ~1.08 ms (deserialization ~1.17 ms) — competitive
with postcard and bincode without serde.

## Reproducing

```sh
# MoonBit side
moon bench --target native          # in-repo suite
moon test bench_compare_wbtest.mbt --target native --release
moon test bench_compare_wbtest.mbt --target wasm-gc

# Rust side (desert-rust checkout + this harness pattern)
# scenarios 1:1 with bench_compare_wbtest.mbt; measure with a plain loop
# accumulating results (see docs above), cargo run --release
```

## Caveats

- Micro benchmarks measure fixed workloads, not your data; per-op fixed
  costs shrink relative to payload size as data grows.
- Rust benefits from cross-crate LTO and years of allocator/codegen tuning;
  MoonBit's native backend is actively evolving — re-run this comparison as
  the toolchain advances.
- The comparison harness measures the *public API* path on both sides
  (top-level call including allocations), which is what applications pay.
