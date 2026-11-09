# Codecs

Every type with a `BinarySerializer` (writes to a `SerializationContext`) and
a `BinaryDeserializer` (reads from a `DeserializationContext`) implementation
is a codec. The context exposes the low-level write/read operations and the
session state (string deduplication).

## Primitives

| Type | Encoding |
|---|---|
| `Byte` | 1 raw byte |
| `Bool` | 1 byte, `0x01`/`0x00` |
| `UInt16` | 2 bytes, big-endian |
| `Int` / `UInt` | 4 bytes, big-endian (two's complement for `Int`) |
| `Int64` / `UInt64` | 8 bytes, big-endian |
| `Float` | 4 bytes IEEE-754 bits, big-endian |
| `Double` | 8 bytes IEEE-754 bits, big-endian |
| `Unit` | zero bytes |
| `Char` | raw varint of the Unicode scalar value; with `Options::scala_compatible()` one big-endian UTF-16 unit (astral characters fail) |
| `String` | zigzag varint of the UTF-8 byte length, then UTF-8 bytes |
| `Bytes` | unsigned varint length + raw bytes (the byte-block form used by `Chunk[Byte]` in Scala and `Vec<u8>` in Rust) |

## Wrappers

- `T?` (`Option`): `0x01` + payload for `Some`, `0x00` for `None`.
- `Result[T, E]`: `0x01` + payload for `Ok`, `0x00` + payload for `Err` —
  the stand-in for Scala's `Either`.
- `DeduplicatedString`: first occurrence is a normal string; repeats are the
  zigzag-encoded negative session id. See below.
- Tuples `(A, B, ...)`: a version-0 record — `0x00` version byte followed by
  the element payloads. A version-0 struct is wire-identical to a tuple of
  the same shape, so tuples can be read as structs and vice versa.

## Collections

Generic collections use two forms; readers accept both, so data written from
any implementation or collection type interoperates:

- **Counted**: zigzag varint length followed by that many element payloads.
- **Unknown size**: zigzag varint `-1`, then `0x01` + payload per element,
  terminated by `0x00`.

Implemented for `Array[T]`, `Map[K, V]`, `@hashmap.HashMap[K, V]`, and
`@hashset.HashSet[T]`. Maps serialize entries as key/value pairs, each pair
written as a 2-tuple (a leading `0x00` per entry). Entry order is the
collection's iteration order and is not canonicalized; cross-implementation
compatibility holds because both sides accept any order.

`Bytes` uses the dedicated byte-block encoding (unsigned varint prefix) rather
than the generic collection form.

`write_iter_unknown_size` serializes a lazy iterator using the unknown-size
form for streaming use cases.

## String deduplication

`DeduplicatedString::new(s)` opts a value into session-wide deduplication.
The first occurrence is written as a normal string and registered in the
per-call state (ids start at 1, assigned in first-occurrence order); every
repeat is written as the zigzag varint of the negative id. On read, every
inline string is registered, and an unknown negative id fails with
`InvalidStringId`.

Do not mix deduplicated and plain string fields inside evolvable records: an
older reader skipping a newly added deduplicated field would miss an id
assignment and corrupt every later back-reference. Plain `String` fields are
always evolution-safe.

The evolution machinery shares the same session state — removed-field names
in evolution headers are written as deduplicated strings — so ids stay
consistent across a whole top-level call.

## Compressed byte blocks

`write_compressed` / `read_compressed` encode a byte block as
`var_u32(uncompressed_length)`, `var_u32(compressed_length)`, raw DEFLATE
data — matching desert-rust's `write_compressed`/`read_compressed`. The
compression itself is provided by `moonbitlang/core/compress/flate`.
