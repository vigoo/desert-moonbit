# Input and output

Serialization writes through the `BinaryOutput` trait; deserialization reads
from `BinaryInput`, a cursor over immutable `Bytes`.

## BinaryOutput

Only two operations are required to implement the trait — `write_u8` and
`write_bytes` — everything else (fixed-width big-endian primitives, floats,
both varint flavors) has a default implementation built on them. The
built-in `ByteOutput` overrides the fixed-width operations with the bulk
fast paths of the core `Buffer`.

```mbt
let out = @desert.ByteOutput::new(capacity=1024)
let ctx = @desert.SerializationContext::new(
  out,
  @desert.SerializerState::new(),
  @desert.Options::default(),
)
value.serialize(ctx)
let bytes = out.to_bytes()
```

The `SerializationContext` itself implements `BinaryOutput`, so codec code
writes through the context: `ctx.write_u8(...)`, `ctx.write_var_i32(...)`,
etc. The evolution machinery swaps the active sink with
`push_output`/`pop_output` to capture generation chunks.

## BinaryInput

A cursor over a `Bytes` value with bounds checking against the current
region limit; underruns raise `InputEndedUnexpectedly`. Reads are zero-copy:
`read_bytes_view` returns a view into the underlying buffer.

```mbt
let input = @desert.BinaryInput::new(bytes)
let ctx = @desert.DeserializationContext::new(
  input,
  @desert.SerializerState::new(),
  @desert.Options::default(),
)
let value : MyType = @desert.BinaryDeserializer::deserialize(ctx)
```

The evolution machinery fences chunk reads with `push_region`/`pop_region`,
so a malformed chunk cannot over-read into the next one.

## Options

Per-call `Options` control wire-format variants; both sides must agree:

- `chars_as_u16` — encode `Char` as one big-endian UTF-16 unit, matching the
  Scala library (astral characters fail with `UnsupportedCharacter`). The
  default encodes the scalar value as a raw varint (desert-rust behavior).
  `Options::scala_compatible()` is a shorthand for the Scala-compatible set.

The defaults (no options set) match desert-rust.

## Sessions

Every top-level call (`serialize_to_bytes`, `deserialize`, ...) creates a
fresh session state: string-dedup ids and reference ids never leak between
calls, matching the behavior of both original implementations.
