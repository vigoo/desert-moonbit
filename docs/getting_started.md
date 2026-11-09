# Getting started with desert for MoonBit

`vigoo/desert` is a binary serialization library for MoonBit. It focuses on
compact binary data while still allowing compatible changes to records and
enums over time.

This package is the counterpart of the original Scala
[desert](https://github.com/vigoo/desert) library and of
[desert-rust](https://github.com/vigoo/desert-rust). The wire format is
byte-compatible with both: data written by one implementation can be read by
the others (given the same schema and options).

## Installation

Add the dependency to `moon.mod`:

```
moon add vigoo/desert
```

and import it in the package's `moon.pkg`:

```
import {
  "vigoo/desert",
}
```

## Serializing and deserializing

Any type with a `BinarySerializer` and a `BinaryDeserializer` implementation
works with the top-level functions:

```mbt
// Serialize to in-memory bytes (raises DesertFailure on I/O errors)
let bytes = @desert.serialize_to_bytes(value)

// Read back; deserialize_exhaustive also rejects trailing bytes
let back : MyType = @desert.deserialize_exhaustive(bytes)
```

`serialize_to_output` writes into a caller-owned `ByteOutput` (useful for
appending to a larger buffer), and `serialized_size` measures the encoded
size without materializing the bytes.

## Deriving codecs for your types

Annotate a struct or enum with the (compiler-inert) `#desert` attribute and
run the generator:

```mbt
#desert(binary_codec)
struct Point {
  x : Int
  y : Int
}
```

```sh
moon run desert/codegen -- <your-package-directory>
```

The generator writes a `desert_derive.mbt` file next to your sources with the
`BinarySerializer`/`BinaryDeserializer` implementations, and adds the
`vigoo/desert` import to the package's `moon.pkg` if missing. Re-run the
command after changing annotated types; the output is deterministic and
formatted with the official MoonBit formatter.

Supported attribute arguments:

- `evolution(FieldAdded("field", default), FieldMadeOptional("field"),
  FieldRemoved("field"), FieldMadeTransient("field"))` — declares the schema
  history; see [evolution.md](evolution.md).
- `type_id = "pkg.TypeName"` — also generates `RegisteredValue`
  implementations for use with the type registry.
- `sorted_constructors` (enums) — assigns constructor ids in lexical order
  instead of declaration order, keeping ids stable when cases are reordered.
- Per-field `#transient(expr)` — the field occupies no wire bytes; `expr` is
  used as its value on read.
- Per-case `#desert(transient)` (enums) — the case cannot be serialized and
  consumes no constructor id.
- Per-case `#desert(transparent)` — the single payload field is written as-is
  without a case version byte.

## Writing codecs by hand

The same engine the generator targets is public, so hand-written codecs have
full control:

```mbt
let metadata = @desert.AdtMetadata::new([@desert.InitialVersion])

impl @desert.BinarySerializer for Point with serialize(self, ctx) {
  let writer = @desert.AdtWriter::new_v0(metadata, ctx)
  writer.write_field("x", self.x)
  writer.write_field("y", self.y)
  writer.finish()
}

impl @desert.BinaryDeserializer for Point with deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    @desert.AdtReader::new_v0(metadata, ctx)
  } else {
    @desert.AdtReader::new(metadata, ctx, stored)
  }
  { x: reader.read_field("x", None), y: reader.read_field("y", None) }
}
```

For un-evolved records the generated code takes a direct fast path (version
byte + inline field reads); the `AdtWriter`/`AdtReader` engine handles
evolution. See [codecs.md](codecs.md) for the primitive codec list and
[wire_format.md](wire_format.md) for the exact byte layout.

## Errors

All failures surface as a typed error, `@desert.DesertFailure`, with a
variant per failure mode (`InputEndedUnexpectedly`, `InvalidStringId`,
`FieldRemovedInSerializedVersion`, ...). Codec code raises it; applications
catch it like any MoonBit error.

## Platform support

The library is pure MoonBit with no FFI and runs on every stable target:
`wasm`, `wasm-gc`, `js`, and `native`. The test suite runs identically on
all four.
