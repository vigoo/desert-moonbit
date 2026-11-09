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
[type registry](docs/type_registry.md).

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
- **Compressed byte blocks** (DEFLATE via `moonbitlang/core/compress`)
- **Pure MoonBit, no FFI** — runs on wasm, wasm-gc, js, and native
- Property-based tests (`moonbitlang/quickcheck`) and micro benchmarks
  (`moon bench`)

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
moon run codegen -- <your-package-directory>
```

## Development

```sh
moon check                  # type check (0 warnings policy)
moon test                   # byte-exact, evolution, registry, property tests
moon bench                  # micro benchmarks
moon run codegen -- codegen_demo   # regenerate the demo codecs
moon info && moon fmt       # refresh interface + format
```
