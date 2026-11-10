# desert for MoonBit

A MoonBit implementation of the [desert](https://github.com/vigoo/desert)
binary serialization format, wire-compatible with the original Scala library
and [desert-rust](https://github.com/vigoo/desert-rust).

Documentation: see the [docs/](docs/index.md) chapters —
[getting started](docs/getting_started.md),
[codecs](docs/codecs.md),
[schema evolution](docs/evolution.md),
[wire format reference](docs/wire_format.md),
[input/output](docs/input_output.md),
[type registry](docs/type_registry.md),
[benchmarks](docs/benchmarks.md).

See my a [conference talk from 2022 about the original Scala version](https://blog.vigoo.dev/posts/funscala2022-talk/).

## Features

- **Byte-compatible wire format** with desert (Scala) and desert-rust,
  pinned by the shared golden dataset (`dataset1.bin`, 242,540 bytes written
  by the Scala library) and byte-exact cross-implementation dumps
- **Schema evolution**: versioned records with field add/remove/
  make-optional/make-transient, forward and backward compatible reads, and
  unknown-step tolerance
- **Code generation**: `#desert(binary_codec)` annotations produce codec
  implementations via the MoonBit-native `desert-codegen` tool (parse →
  validate → format pipeline, idempotent output)
- **Opt-in string deduplication** (`DeduplicatedString`) with session-scoped
  ids, shared with the evolution headers
- **Type registry** for runtime-dispatched ("unknown") serialization
- Known limitation: object back-reference tracking (Scala
  `storeRefOrObject`) is not implemented yet; see docs/codecs.md
- **Compressed byte blocks** (DEFLATE via `moonbitlang/core/compress`)
- **Pure MoonBit, no FFI** — runs on wasm, wasm-gc, js, and native
- Property-based tests (`moonbitlang/quickcheck`) and micro benchmarks
  (`moon bench`) — see the [desert-rust comparison report](docs/benchmarks.md)

## Usage

```mbt nocheck
// Serialize / deserialize (raises @desert.DesertFailure on errors)

///|
let bytes = @desert.serialize_to_bytes(value)

///|
let back : MyType = @desert.deserialize_exhaustive(bytes)
```

```mbt nocheck
// Derive codecs for your types

///|
#desert(binary_codec, evolution(FieldAdded("extra", "default")))
struct MyRecord {
  base : Int32
  extra : String
}
```

```sh
# from a clone of this repository (a MoonBit workspace):
moon run codegen -- <your-package-directory>
```

## Project layout

MoonBit organizes code into **packages** — each directory with a `moon.pkg`
is one package and one namespace, imported as `@desert` (or
`vigoo/desert/codegen` for subpackages). Files *within* a package are pure
organization: they do not define namespaces (unlike Java/C#/Rust modules),
and splitting code across topical files is the standard idiom — see
`moonbitlang/core/builtin` (241 `.mbt` files) and `moonbitlang/quickcheck`
in the standard ecosystem. This repository follows that shape:

```
moon.mod            module metadata (published as vigoo/desert)
moon.pkg            the root package — the library itself
error.mbt           DesertFailure taxonomy
binary_input.mbt    read cursor (BinaryInput)
binary_output.mbt   write sink (BinaryOutput + ByteOutput)
codecs_*.mbt        primitive/string/collection/tuple codecs
evolution.mbt       evolution metadata + wire codes
adt_writer.mbt      evolved-record writer engine
adt_reader.mbt      evolved-record reader engine
state.mbt           per-session dedup state
registry.mbt        type registry
compressed.mbt      DEFLATE byte blocks
facade.mbt          top-level serialize/deserialize
*_test.mbt / *_wbtest.mbt   blackbox / whitebox tests
codegen/            desert-codegen generator (executable package)
codegen_demo/       generated-code golden test package
docs/               documentation chapters
```

The generated `pkg.generated.mbti` file is the package's public API surface
(the equivalent of Rust's `lib.rs` exports — run `moon info` to refresh it).

## Development

```sh
moon check                  # type check (0 warnings policy)
moon test                   # byte-exact, evolution, registry, property tests
moon bench                  # micro benchmarks
moon run codegen -- codegen_demo   # regenerate the demo codecs
moon info && moon fmt       # refresh interface + format
```
