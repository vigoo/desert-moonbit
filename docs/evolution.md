# Schema evolution

desert's defining feature: records and enums carry enough metadata on the
wire for a *newer* reader to decode *older* data and an *older* reader to
decode *newer* data — without any external schema store.

## Declaring a history

A record's evolution is a list of steps starting from `InitialVersion`. The
list length minus one is the version byte stored in every payload:

```mbt
#desert(binary_codec, evolution(
  FieldAdded("theme", "light"),
  FieldMadeOptional("nickname"),
))
struct Settings {
  volume : Int
  nickname : String?
  theme : String
}
```

The four step kinds:

- `FieldAdded(name, default)` — the field exists from version N on. New
  readers fill older data with `default`; old readers ignore the extra chunk.
- `FieldMadeOptional(name)` — the field used to be required. New readers
  read older data as a bare value wrapped in `Some`; old readers can read
  newer data only when the value is defined (`None` fails with
  `NonOptionalFieldSerializedAsNone`).
- `FieldRemoved(name)` — new readers skip the old bytes; old readers fail
  with `FieldRemovedInSerializedVersion` (for optional fields the read is
  `None`).
- `FieldMadeTransient(name)` — wire-level alias of `FieldRemoved`: the value
  is not serialized at all, and readers supply the `#transient(expr)`
  default locally.

## Wire layout

For a record with version `V > 0`:

1. the version byte `V`;
2. the **evolution header**: `V + 1` entries, one per step, in order;
3. the **chunks**: the record's fields grouped by generation (which
   `FieldAdded` step introduced them), each generation's bytes concatenated
   in version order.

Header entries (all zigzag varints):

| Step | Encoding |
|---|---|
| `InitialVersion` / `FieldAdded` | byte length of that generation's chunk |
| `FieldMadeOptional` | `-1`, then a packed field-position byte |
| `FieldRemoved` / `FieldMadeTransient` | `-2`, then the field name as a deduplicated string |
| unknown step (from a future version) | `0`, ignored by older readers |

The field-position byte packs `(chunk, position)`: for chunk 0 it is the
negated position, otherwise the chunk number (position 0 implied). This
matches the original implementations byte for byte.

Version 0 records have no header and no chunks: just the `0x00` version byte
and the fields in declaration order — byte-identical to a tuple of the same
shape.

## Enums

The enum itself writes a version byte (currently always 0), then the
constructor index as an unsigned varint, then the case payload as its own
evolvable record (case version byte, fields, optional case-level header).

Constructor ids are assigned in declaration order, skipping transient cases;
`sorted_constructors` assigns ids in lexical order instead, which keeps ids
stable when cases are reordered. Adding a case at the end is compatible for
new readers; old readers fail on the unknown id with `InvalidConstructorId`.

## Reading rules

The `AdtReader` implements the compatibility matrix:

- a field whose generation is newer than the stored version falls back to
  its `FieldAdded` default (or fails with
  `FieldWithoutDefaultValueIsMissing`);
- a field removed in the serialized version fails on read;
- a field made optional *after* the stored version is read bare and wrapped
  in `Some`;
- an old reader finding a made-optional field serialized as `None` fails;
- unknown header entries from future versions are ignored;
- every chunk read is fenced by an input region, so a misaligned or
  truncated chunk cannot bleed into neighboring data.

These rules are pinned by tests in both directions, including the byte-exact
worked example shared with the Scala and Rust implementations:

```
evolution: FieldAdded("x", 0), FieldRemoved("z"); transient cached_str
Point(1, -10, None) =>
02 | 08 | 08 | 03 02 7A | FF FF FF F6 | 00 00 00 01
```

## The golden dataset

`golden_data.mbt` embeds the 242,540-byte `dataset1.bin` produced by the
Scala library (also used by desert-rust's golden test). The golden test
deserializes it field by field — scalars, UUID, nested exceptions with 16
stack frames and a cause, collections, sorted-constructor enums with a
transient case, deduplicated strings, an evolved record with a
made-optional map — and round-trips it. This is the ultimate proof of
cross-implementation wire compatibility.
