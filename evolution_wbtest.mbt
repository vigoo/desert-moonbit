///|
fn[T : BinarySerializer] ser_evolved(value : T) -> Bytes {
  let res : Result[Bytes, DesertFailure] = Ok(serialize_to_bytes(value)) catch {
    e => Err(e)
  }
  match res {
    Ok(b) => b
    Err(f) => abort("serialization failed: \{f}")
  }
}

///|
fn[T : BinaryDeserializer] deser_evolved(data : Bytes) -> T {
  let res : Result[T, DesertFailure] = Ok(deserialize_exhaustive(data)) catch {
    e => Err(e)
  }
  match res {
    Ok(v) => v
    Err(f) => abort("deserialization failed: \{f}")
  }
}

///|
/// Byte-exact tests for the evolution engine, using the same worked example
/// as the Scala and Rust implementations:
///
/// evolution steps: `FieldAdded("x", 0)`, `FieldRemoved("z")` — so the
/// record has version 2; `x` belongs to chunk 1, `y` (and the removed `z`)
/// to chunk 0, and `cached_str` is a transient field (no wire bytes).
///
/// Serialized `Point(1, -10, None)` must produce exactly
/// `02 08 08 03 02 7A FF FF FF F6 00 00 00 01`, byte-for-byte identical to
/// what desert-scala and desert-rust produce.

///|
#derive(Debug, Eq)
struct Point {
  x : Int32
  y : Int32
  cached_str : String?
}

///|
let point_metadata : AdtMetadata = AdtMetadata::new([
  InitialVersion,
  FieldAdded("x"),
  FieldRemoved("z"),
])

///|
impl BinarySerializer for Point with fn serialize(self, ctx) {
  let writer = AdtWriter::new(point_metadata, ctx)
  writer.write_field("x", self.x)
  writer.write_field("y", self.y)
  writer.finish()
}

///|
impl BinaryDeserializer for Point with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(point_metadata, ctx)
  } else {
    AdtReader::new(point_metadata, ctx, stored)
  }
  let x = reader.read_field("x", Some(0))
  let y = reader.read_field("y", None)
  // `cached_str` is transient: it is never (de)serialized, only defaulted.
  let cached : String? = None
  { x, y, cached_str: cached, }
}

///|
test "evolved point byte exact serialization" {
  let bytes = ser_evolved(Point::{ x: 1, y: -10, cached_str: None, })
  assert_eq(bytes, b"\x02\x08\x08\x03\x02\x7a\xff\xff\xff\xf6\x00\x00\x00\x01")
}

///|
test "evolved point byte exact deserialization" {
  let bytes : Bytes = b"\x02\x08\x08\x03\x02\x7a\xff\xff\xff\xf6\x00\x00\x00\x01"
  let res : Result[Point, DesertFailure] = Ok(deserialize_exhaustive(bytes)) catch {
    e => Err(e)
  }
  match res {
    Ok(point) => {
      assert_eq(point.x, 1)
      assert_eq(point.y, -10)
    }
    Err(f) => abort("\{f}")
  }
}

///|
test "version 0 record is wire identical to tuple" {
  // Verified against desert-rust: struct {a: i32=1, b:"x"} == (i32, String)
  let bytes = ser_evolved(V0Point::{ a: 1, b: "x", })
  assert_eq(bytes, b"\x00\x00\x00\x00\x01\x02\x78")
  let round : V0Point = deser_evolved(bytes)
  assert_eq(round.a, 1)
  assert_eq(round.b, "x")
}

///|
/// New reader (version 1: `FieldAdded("extra", default)`) reading data
/// written by a version-0 writer: `extra` falls back to its default.
#derive(Debug, Eq)
struct WithExtra {
  base : Int32
  extra : String
}

///|
let with_extra_metadata : AdtMetadata = AdtMetadata::new([
  InitialVersion,
  FieldAdded("extra"),
])

///|
impl BinarySerializer for WithExtra with fn serialize(self, ctx) {
  let writer = AdtWriter::new(with_extra_metadata, ctx)
  writer.write_field("base", self.base)
  writer.write_field("extra", self.extra)
  writer.finish()
}

///|
impl BinaryDeserializer for WithExtra with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(with_extra_metadata, ctx)
  } else {
    AdtReader::new(with_extra_metadata, ctx, stored)
  }
  let base = reader.read_field("base", None)
  let extra = reader.read_field("extra", Some("fallback"))
  { base, extra, }
}

///|
test "new reader fills defaults for fields missing in old data" {
  // Version-0 payload: version byte + base only (no header).
  let old_data : Bytes = b"\x00\x00\x00\x00\x2a"
  let res : Result[WithExtra, DesertFailure] = Ok(
    deserialize_exhaustive(old_data),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(value) => {
      assert_eq(value.base, 42)
      assert_eq(value.extra, "fallback")
    }
    Err(f) => abort("\{f}")
  }
  // The same reader writing its own (version 1) form round-trips exactly.
  let round : WithExtra = deser_evolved(
    ser_evolved(WithExtra::{ base: 7, extra: "x", }),
  )
  assert_eq(round.base, 7)
  assert_eq(round.extra, "x")
}

///|
test "old reader fails on new data without defaults" {
  // Data written with version 1 (header + chunk) is read back by a codec
  // with no default for `extra`: the read must fail.
  let old_data : Bytes = b"\x00\x00\x00\x00\x2a"
  let res : Result[NoDefaults, DesertFailure] = Ok(
    deserialize_exhaustive(old_data),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(FieldWithoutDefaultValueIsMissing("extra")) => ()
    Err(other) =>
      abort("expected FieldWithoutDefaultValueIsMissing, got \{other}")
    Ok(_) => abort("expected a failure")
  }
}

///|
test "reader fails on removed field still present in model" {
  // `z` was removed by the writer's evolution but the reader model still
  // requires it (Point has no `z` field anymore; simulate by asking for it).
  let bytes : Bytes = b"\x02\x08\x08\x03\x02\x7a\xff\xff\xff\xf6\x00\x00\x00\x01"
  let res : Result[LegacyPoint, DesertFailure] = Ok(
    deserialize_exhaustive(bytes),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(FieldRemovedInSerializedVersion("z")) => ()
    Err(other) =>
      abort("expected FieldRemovedInSerializedVersion, got \{other}")
    Ok(_) => abort("expected a failure")
  }
}

///|
/// Version-0 record used by the tuple-equivalence test.
#derive(Debug, Eq)
struct V0Point {
  a : Int32
  b : String
}

///|
let v0_point_metadata : AdtMetadata = AdtMetadata::new([InitialVersion])

///|
impl BinarySerializer for V0Point with fn serialize(self, ctx) {
  let writer = AdtWriter::new_v0(v0_point_metadata, ctx)
  writer.write_field("a", self.a)
  writer.write_field("b", self.b)
  writer.finish()
}

///|
impl BinaryDeserializer for V0Point with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(v0_point_metadata, ctx)
  } else {
    AdtReader::new(v0_point_metadata, ctx, stored)
  }
  let a = reader.read_field("a", None)
  let b = reader.read_field("b", None)
  { a, b, }
}

///|
/// Same shape as `WithExtra` but no default for `extra`, so reading old data
/// must fail with `FieldWithoutDefaultValueIsMissing`.
#derive(Debug, Eq)
struct NoDefaults {
  base : Int32
  extra : String
}

///|
let no_defaults_metadata : AdtMetadata = AdtMetadata::new([
  InitialVersion,
  FieldAdded("extra"),
])

///|
impl BinaryDeserializer for NoDefaults with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(no_defaults_metadata, ctx)
  } else {
    AdtReader::new(no_defaults_metadata, ctx, stored)
  }
  let base = reader.read_field("base", None)
  let extra = reader.read_field("extra", None)
  { base, extra, }
}

///|
/// Model that still declares the `z` field which the serialized `Point`
/// data has removed.
#derive(Debug, Eq)
struct LegacyPoint {
  x : Int32
  y : Int32
  z : Int32
}

///|
let legacy_point_metadata : AdtMetadata = AdtMetadata::new([
  InitialVersion,
  FieldAdded("x"),
  FieldRemoved("z"),
])

///|
impl BinaryDeserializer for LegacyPoint with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(legacy_point_metadata, ctx)
  } else {
    AdtReader::new(legacy_point_metadata, ctx, stored)
  }
  let x = reader.read_field("x", Some(0))
  let y = reader.read_field("y", None)
  let z = reader.read_field("z", None)
  { x, y, z, }
}

///|
pub extend Point with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend V0Point with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WithExtra with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend NoDefaults with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend LegacyPoint with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Point with Eq::{not_equal, equal}

///|
pub extend V0Point with Eq::{not_equal, equal}

///|
pub extend WithExtra with Eq::{not_equal, equal}

///|
pub extend NoDefaults with Eq::{not_equal, equal}

///|
pub extend LegacyPoint with Eq::{not_equal, equal}

///|
/// `FieldMadeOptional` — writer has the field optional (version 1); an old
/// reader (version 0, field still non-optional) must read the boolean guard
/// and fail on `None`.

///|
/// The NEW model: `flag` was made optional.
#derive(Debug, Eq)
struct OptionalizedNew {
  base : Int32
  flag : Bool?
}

///|
let optionalized_new_metadata : AdtMetadata = AdtMetadata::new([
  InitialVersion,
  FieldMadeOptional("flag"),
])

///|
impl BinarySerializer for OptionalizedNew with fn serialize(self, ctx) {
  let writer = AdtWriter::new(optionalized_new_metadata, ctx)
  writer.write_field("base", self.base)
  writer.write_field("flag", self.flag)
  writer.finish()
}

///|
/// The OLD model: `flag` is still non-optional.
#derive(Debug, Eq)
struct OptionalizedOld {
  base : Int32
  flag : Bool
}

///|
let optionalized_old_metadata : AdtMetadata = AdtMetadata::new([InitialVersion])

///|
impl BinaryDeserializer for OptionalizedOld with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(optionalized_old_metadata, ctx)
  } else {
    AdtReader::new(optionalized_old_metadata, ctx, stored)
  }
  let base = reader.read_field("base", None)
  let flag = reader.read_field("flag", None)
  { base, flag, }
}

///|
test "old reader accepts made-optional field when defined" {
  // New writer: version 1 with flag = Some(true).
  let data = ser_evolved(OptionalizedNew::{ base: 5, flag: Some(true), })
  let value : OptionalizedOld = deser_evolved(data)
  assert_eq(value.base, 5)
  assert_eq(value.flag, true)
}

///|
test "old reader fails on made-optional field serialized as none" {
  let data = ser_evolved(OptionalizedNew::{ base: 5, flag: None, })
  let res : Result[OptionalizedOld, DesertFailure] = Ok(
    deserialize_exhaustive(data),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(NonOptionalFieldSerializedAsNone("flag")) => ()
    Err(other) =>
      abort("expected NonOptionalFieldSerializedAsNone, got \{other}")
    Ok(_) => abort("expected a failure")
  }
}

///|
/// Forward compatibility: a version-0 reader (whose metadata has no idea
/// about newer steps) can read data written by a version-2 writer — the
/// newer fields live in chunks the old reader never touches.
#derive(Debug, Eq)
struct OnlyBase {
  base : Int32
}

///|
let only_base_metadata : AdtMetadata = AdtMetadata::new([InitialVersion])

///|
impl BinaryDeserializer for OnlyBase with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(only_base_metadata, ctx)
  } else {
    AdtReader::new(only_base_metadata, ctx, stored)
  }
  { base: reader.read_field("base", None), }
}

///|
test "old reader skips future chunks" {
  // Data written by WithExtra (version 1: base + extra chunk).
  let data = ser_evolved(WithExtra::{ base: 9, extra: "new", })
  let value : OnlyBase = deser_evolved(data)
  assert_eq(value.base, 9)
}

///|
/// Reading data written by a newer version that made a field optional: the
/// new reader wraps bare old values in `Some`.
#derive(Debug, Eq)
struct GrewOptional {
  name : String?
}

///|
let grew_optional_metadata : AdtMetadata = AdtMetadata::new([
  InitialVersion,
  FieldMadeOptional("name"),
])

///|
impl BinarySerializer for GrewOptional with fn serialize(self, ctx) {
  let writer = AdtWriter::new(grew_optional_metadata, ctx)
  writer.write_field("name", self.name)
  writer.finish()
}

///|
impl BinaryDeserializer for GrewOptional with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(grew_optional_metadata, ctx)
  } else {
    AdtReader::new(grew_optional_metadata, ctx, stored)
  }
  { name: reader.read_optional_field("name", None), }
}

///|
test "new reader wraps bare old value in some" {
  // Version-0 writer: bare string (zigzag length 4 -> 0x08), no option tag,
  // no header.
  let old_data : Bytes = b"\x00\x08\x74\x65\x73\x74"
  let value : GrewOptional = deser_evolved(old_data)
  assert_eq(value.name, Some("test"))
  // Version-1 writer: option tag present.
  let new_data = ser_evolved(GrewOptional::{ name: Some("x"), })
  let value2 : GrewOptional = deser_evolved(new_data)
  assert_eq(value2.name, Some("x"))
  let none_data = ser_evolved(GrewOptional::{ name: None, })
  let value3 : GrewOptional = deser_evolved(none_data)
  assert_eq(value3.name, None)
}

///|
pub extend OptionalizedNew with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend OptionalizedNew with Eq::{not_equal, equal}

///|
pub extend OptionalizedOld with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend OptionalizedOld with Eq::{not_equal, equal}

///|
pub extend OnlyBase with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend OnlyBase with Eq::{not_equal, equal}

///|
pub extend GrewOptional with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend GrewOptional with Eq::{not_equal, equal}
