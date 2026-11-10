# Pre-publish review — vigoo/desert (MoonBit port of desert)

Date: 2026-11-10 · Reviewer: ZCode agent · Scope: full read-through of the
root package (6,208 lines across 32 files), public interface
(`pkg.generated.mbti`), codegen tool + demo, tests (118 test blocks), docs
(8 chapters), benchmarks, packaging. Reference baselines: desert (Scala,
e6d7803) and desert-rust (b4302f5) analyses. Two robustness claims were
verified with throwaway probes outside the repo; nothing in the library was
modified.

**Verdict: NOT ready to publish as-is.** The wire format is in excellent,
evidence-backed shape, but there are 3 publish-blockers (packaging/API
hygiene that would be very hard to fix after a 0.1.0 release), 3 confirmed
robustness bugs on malformed input, and a broken documented path for the
flagship "out of the box derivation" story. All are fixable without touching
the wire format.

---

## 1. What's strong (verified)

- **Wire format correctness is proven, not asserted**: byte-exact tests
  against dumps produced by both original implementations; the 242,540-byte
  Scala `dataset1.bin` golden test deserializes field-by-field (nested
  exceptions with 16-frame traces + cause, evolved record, sorted-constructor
  enum with transient case, dedup-in-headers, collections) and round-trips.
- **105 tests green on all four targets** (wasm, wasm-gc, js, native),
  `moon check` at 0 warnings. Property tests previously caught a real
  surrogate-pair encoding bug — the suite has teeth.
- **Evolution engine is faithful**, including subtle behaviors I re-verified
  by hand this review: two-pass header parsing (entries first, chunks sliced
  sequentially), region fencing per chunk, signed `FieldPosition` byte
  (read via `read_i8` — the earlier zero-extension bug was fixed), made-
  optional semantics in both directions, unknown-step (code 0) tolerance,
  size-0 chunks decoding as Unknown (matches desert-rust exactly).
- **A subtle equivalence I specifically hunted for is safe**: the reader
  keys `made_optional_at` by the packed position byte, which discards the
  position for chunks > 0 (desert-rust keys by full `FieldPosition`). These
  are equivalent because every non-zero generation chunk contains exactly
  one field (each `FieldAdded` step adds one field; multi-field chunks exist
  only in generation 0, where the byte is `-position` — unique). Not a bug;
  worth a code comment someday.
- **Performance work is honest and documented**: MoonBit native *wins* on
  golden-dataset serialize (226 µs vs Rust 274 µs) and dedup back-reference
  deserialize; reuse APIs close most of the small-op gap; three attempted
  optimizations that regressed were reverted and recorded as findings
  (F10/F13) in OPTIMIZATION_PLAN.md.
- Docs (8 chapters) are accurate on the wire format and candid about
  divergences; the benchmark report includes negative results.

## 2. Publish-blockers (decide before `moon publish`)

**PB1 — Golden dataset ships in the published root package.**
`golden_data.mbt` (999 KB of generated source embedding 242,540 bytes) plus
`testdata/dataset1.bin` (242 KB) and `scripts/` live in the root package,
and `pub fn golden_dataset1() -> Bytes` is part of the public API
(pkg.generated.mbti line 22). Consequences: every consumer compiles ~1 MB of
test fixture into their build; test infrastructure is public API (and once
published, removing it is a breaking change). Fix direction: move
`golden_data.mbt` + dataset into a test-only location (e.g. the golden test
package or `for "test"` scoped file set) and unpublish the symbol.

**PB2 — Module-level dependencies on `moonbitlang/parser@0.4.7` and
`moonbitlang/x@0.5.7`.** These exist solely for the `codegen` executable
package but are declared in `moon.mod`'s import block, so every consumer of
`vigoo/desert` resolves and downloads them. Additionally, `codegen` (a
build tool) and `codegen_demo` (a demo/test package) would be published as
`vigoo/desert/codegen` and `vigoo/desert/codegen_demo`. Fix direction: split
the generator into its own module (e.g. `vigoo/desert-codegen`) depending on
`vigoo/desert`; keep the published module dependency-free beyond core.

**PB3 — The documented derivation flow does not work for external users.**
`docs/getting_started.md` instructs `moon run desert/codegen -- <dir>` (the
package is actually `codegen` in this repo), but fundamentally `moon run`
executes *workspace* packages: a consumer who installs `vigoo/desert` from
mooncakes cannot run the generator this way at all. Since "derive without
manual code" is the headline feature, 0.1.0 should ship a usable story —
e.g. publish the generator as an installable executable/module with
accurate instructions — or the docs must clearly state the vendoring step.

## 3. High — confirmed robustness bugs (hostile/corrupt input)

**H1 — Uncatchable trap on malformed `Bytes` length.**
`Bytes::deserialize` does `read_var_u32().reinterpret_as_int()` then
`read_bytes(len)`; a length ≥ 2^31 reinterprets negative, `ensure()`
passes (its check is `remaining < count`, false for negative), and
`exact_view(end < start)` **traps** — probe confirmed:
`Invalid index for View → RuntimeError: unreachable`, not a
`DesertFailure`. Same class of issue: `read_bytes_view(negative)` and
`skip(negative)` via the public context API. Fix direction: reject
negative counts with `DeserializationFailure` at the entry points.

**H2 — `Char` decode accepts invalid code points silently.** Default-mode
`Char::deserialize` calls `cp.unsafe_to_char()` without validation; probe
confirmed `unsafe_to_char(0x110000)`, `(0xD800)` (surrogate) and even
`(0xFFFFFFFF)` (→ Char whose `to_int()` is **-1**) all succeed, producing
invalid `Char`s. desert-rust validates and fails. A corrupt stream yields
garbage instead of `FailedToDecodeCharacter`. (The `chars_as_u16` path is
correctly validated.)

**H3 — `read_compressed` robustness.** The stored `uncompressed_len` is
only used for the empty-block check; the decompressed size is never
verified against it, and `@flate.inflate_exact` is invoked without
`max_output` — a decompression-bomb vector on hostile input. Also there is
no cross-language compressed-block test (docs correctly note Scala writes a
different empty-block shape, but that divergence is untested against real
Scala data).

## 4. Medium — feature/API gaps vs references and surface leaks

- **M1: No `Int16` codec.** MoonBit has `Int16` (verified during port
  analysis) but only `UInt16` got a `BinarySerializer/Deserializer` impl;
  `Array[Int16]` etc. won't serialize. Raw `write_i16/read_i16` exist
  (Int32-based). Scala/Rust both cover i16.
- **M2: Object reference tracking is missing.** Both Scala
  (`storeRefOrObject`/`readRefOrValue`) and Rust (`store_ref_or_object`/
  `try_read_ref`) ship it for cyclic graphs; this port has neither, yet
  `InvalidRefId` exists in the public error taxonomy as dead code (nothing
  ever raises it). Either implement or remove the variant + document the
  gap.
- **M3: Codegen feature gaps vs the Rust derive:** (a) transparent *unit*
  cases are rejected (`arity != 1` check) though Rust supports them; (b)
  enum **container-level** evolution is unsupported — generated enums write
  version 0 and reject non-zero on read, while the Rust derive supports
  evolution steps on enum containers; (c) no `custom = Type` wrapper
  equivalent.
- **M4: Public-API leaks.** `BinaryInput::seek_internal` (internal,
  unchecked, misnamed for public use); `ByteOutput.buffer` field;
  `DeduplicatedString.string` field (plus a redundant `get()`);
  `AdtMetadata` with all fields public — users can construct inconsistent
  metadata (e.g. `version` disagreeing with `evolution_steps`), and
  `contains_field_made_optional` is an internal cache detail;
  `RegisteredEntry.deserialize` is a raw public function field;
  `utf8_byte_length`/`write_utf8`/`read_utf8` are implementation internals
  (documented, but they hard-code the lone-surrogate `?` policy at the
  wrong layer). Also a **trait-contract inconsistency**:
  `BinaryOutput::write_string_utf8`'s default implementation substitutes
  `?` for lone surrogates, but `ByteOutput`'s override passes through to
  core, which 3-byte-encodes them — the same call produces different bytes
  depending on the sink. (The wire path `write_string_payload` is unaffected
  — it always uses the scratch transcoder.)
- **M5: No version-mode validation in AdtWriter/AdtReader constructors.**
  Rust asserts `metadata.version == 0` in `new_v0`; ours accepts any
  metadata in `new_v0` (silently writing version 0) and an *empty* steps
  array yields `version = -1`, which `to_byte()` would write as `0xFF`.
  Footguns for hand-written codecs; codegen never trips them.
- **M6: `ArrayOfInt` is serializer-only** (documented as opt-in, wire-
  identical; decode via plain `Array[Int]`). Asymmetry is defensible but
  worth a docs note; a deserializer or a wider family (`Int64`/`Double`)
  would round it out.

## 5. Low / cosmetic

- L1: Stale comment in `write_string_payload` — claims the scratch is
  "reused across strings within the session (grown on demand)"; that was
  reverted (F13). The code allocates fresh.
- L2: `serialized_size` docstring says "writing into a discard sink"; it
  actually writes into a real `ByteOutput` (correct result, mild waste).
- L3: `write_constructor` takes `UInt32` while `read_constructor_idx`
  returns `Int32` (reinterpret) — asymmetric types.
- L4: Generated code emits stray empty `///` doc lines; harmless.
- L5: `docs/getting_started.md` codegen command path mismatch (see PB3).
- L6: `DeserializationContext` exposes `input`/`options` as public fields
  while `SerializationContext` hides `output` — asymmetric encapsulation.

## 6. Test & docs assessment

- 118 test blocks; strongest areas: wire-exactness, evolution semantics,
  golden, registry, codegen unit tests, properties. Thinnest: compressed
  blocks (no adversarial-length/roundtrip-size cases beyond the two),
  `Bytes`/`Char` malformed-input paths (exactly where H1/H2 live),
  `Options::scala_compatible` interactions beyond Char.
- Docs are unusually honest (negative benchmark results, Scala compressed
  divergence). Gaps: no mention of M1/M2/M3 limitations; `type_registry.md`
  correctly explains the no-downcast design.

## 7. Pre-publish checklist (ordered)

Status after the fix round (2026-11-10):

1. [x] H1 + H2 fixed — negative-count guards in `read_bytes_view`/
       `read_bytes`/`skip_bytes`, `Bytes` codec rejects ≥2^31 lengths,
       `Char` decode validates code points; tests added.
2. [x] H3 fixed — decompressed size verified against `uncompressed_len`,
       `inflate_exact` called with `max_output`.
3. [x] PB1 — golden data moved to `golden_data_wbtest.mbt` (test-scoped,
       excluded from the published API and consumer builds); `testdata/`
       in `.moonignore`.
4. [x] PB2 — codegen split into its own module
       (`vigoo/desert-codegen`, `codegen/moon.mod`), MoonBit workspace
       (`moon.work`); root `moon.mod` no longer depends on parser/x.
5. [x] PB3 — docs updated (clone + `moon run codegen` story; workspace run
       verified); emission strategy analyzed in `codegen/EMISSION.md`
       (options A–D, recommendation: keep A).
6. [x] M2 — reference tracking documented as not-yet-implemented in
       docs/codecs.md (`InvalidRefId` reserved); implementation deferred
       (needs an object-identity story in MoonBit).
7. [x] M1 — `Int16` codec added (BE two's complement, matches Scala
       Short/Rust i16) with wire+roundtrip tests.
8. [x] M4/M5 — `AdtWriter::new_v0`/`AdtReader::new_v0` validation (writer
       asserts version 0; reader accepts any metadata for stored-0 data,
       matching desert-rust), `AdtMetadata::new` rejects empty steps;
       `seek_internal` removed; `ByteOutput.buffer`,
       `DeduplicatedString.string`, `AdtMetadata` fields,
       `RegisteredEntry` fields made private; context `options`
       accessors added; trait-contract inconsistency resolved by removing
       `write_string_utf8` from `BinaryOutput` (wire path unaffected).
9. [x] L1–L6 fixed (stale comment, docstring, Int32 constructor index,
       stray doc lines, docs paths, field visibility).
10. [x] M3 — codegen: transparent unit cases supported; container-level
       enum evolution explicitly rejected with a clear error; (the
       `custom` wrapper remains unsupported and undocumented as a feature).
11. [ ] Commit all work; final `moon info && moon fmt && moon test` on all
       four targets; `moon bench` canaries re-baselined (done in-repo:
       all green; commit pending).
