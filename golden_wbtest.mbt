///|
/// Cross-language golden test: deserialize the 242540-byte `dataset1.bin`
/// produced by the original Scala desert library (the same binary that
/// desert-rust's `golden_test_1` reads), verify every field, and round-trip
/// it. This pins full byte-level wire compatibility of the MoonBit port.

///|
/// 128-bit UUID: serialized as two big-endian 64-bit halves.
#derive(Debug, Eq)
struct Uuid {
  msb : UInt64
  lsb : UInt64
}

///|
fn Uuid::parse(hex : String) -> Uuid {
  let sb = StringBuilder()
  for i in 0..<hex.length() {
    match hex.get_char(i) {
      Some(c) => if c != '-' { sb.write_char(c) }
      None => ()
    }
  }
  let digits = sb.to_string()
  if digits.length() != 32 {
    abort("invalid uuid: \{hex}")
  }
  fn hex64(s : String) -> UInt64 {
    let mut v = 0UL
    for i in 0..<16 {
      let c = s[i].to_int()
      let d = if c >= '0'.to_int() && c <= '9'.to_int() {
        c - '0'.to_int()
      } else if c >= 'a'.to_int() && c <= 'f'.to_int() {
        c - 'a'.to_int() + 10
      } else {
        abort("invalid hex")
      }
      v = (v << 4) | d.to_uint64()
    }
    v
  }
  { msb: hex64(digits[0:16].to_owned()), lsb: hex64(digits[16:32].to_owned()), }
}

///|
impl BinarySerializer for Uuid with fn serialize(self, ctx) {
  ctx.write_u64(self.msb)
  ctx.write_u64(self.lsb)
}

///|
impl BinaryDeserializer for Uuid with fn deserialize(ctx) {
  let msb = ctx.read_u64()
  let lsb = ctx.read_u64()
  { msb, lsb, }
}

///|
/// Wire `i16` payload wrapper: MoonBit has no 16-bit signed integer type,
/// so the value is carried in an `Int32` (sign-extended).
#derive(Debug, Eq)
struct ShortWire {
  value : Int32
}

///|
impl BinarySerializer for ShortWire with fn serialize(self, ctx) {
  ctx.write_i16(self.value)
}

///|
impl BinaryDeserializer for ShortWire with fn deserialize(ctx) {
  { value: ctx.input.read_i16(), }
}

///|
/// Stack frame, matching the Scala library's `StackTraceElement` codec:
/// an ignored marker byte, three optional strings, and a raw varint line
/// number.
#derive(Debug, Eq)
struct StackFrame {
  class_name : String?
  method_name : String?
  file_name : String?
  line_number : Int32
}

///|
impl BinarySerializer for StackFrame with fn serialize(self, ctx) {
  ctx.write_u8(b'\x00')
  ctx.write(self.class_name)
  ctx.write(self.method_name)
  ctx.write(self.file_name)
  ctx.write_var_u32(self.line_number.reinterpret_as_uint())
}

///|
impl BinaryDeserializer for StackFrame with fn deserialize(ctx) {
  let marker = ctx.read_u8()
  if marker != b'\x00' {
    abort("unexpected stack frame marker")
  }
  let class_name = ctx.read_optional_value()
  let method_name = ctx.read_optional_value()
  let file_name = ctx.read_optional_value()
  let line_number = ctx.read_var_u32().reinterpret_as_int()
  { class_name, method_name, file_name, line_number, }
}

///|
/// Mirrors desert-scala's `PersistedThrowable` record (a version-0 record
/// with a single constructor).
#derive(Debug, Eq)
struct PersistedThrowable {
  class_name : String
  message : String
  stack_trace : Array[StackFrame]
  cause : PersistedThrowable?
}

///|
let throwable_metadata : AdtMetadata = AdtMetadata::new([InitialVersion])

///|
impl BinarySerializer for PersistedThrowable with fn serialize(self, ctx) {
  let writer = AdtWriter::new_v0(throwable_metadata, ctx)
  writer.write_field("class_name", self.class_name)
  writer.write_field("message", self.message)
  writer.write_field("stack_trace", self.stack_trace)
  writer.write_field("cause", self.cause)
  writer.finish()
}

///|
impl BinaryDeserializer for PersistedThrowable with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(throwable_metadata, ctx)
  } else {
    AdtReader::new(throwable_metadata, ctx, stored)
  }
  let class_name = reader.read_field("class_name", None)
  let message = reader.read_field("message", None)
  let stack_trace = reader.read_field("stack_trace", None)
  let cause = reader.read_optional_field("cause", None)
  { class_name, message, stack_trace, cause, }
}

///|
#derive(Debug, Eq)
struct ListElement1 {
  id : String
}

///|
let list_element1_metadata : AdtMetadata = AdtMetadata::new([InitialVersion])

///|
impl BinarySerializer for ListElement1 with fn serialize(self, ctx) {
  let writer = AdtWriter::new_v0(list_element1_metadata, ctx)
  writer.write_field("id", self.id)
  writer.finish()
}

///|
impl BinaryDeserializer for ListElement1 with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(list_element1_metadata, ctx)
  } else {
    AdtReader::new(list_element1_metadata, ctx, stored)
  }
  let id = reader.read_field("id", None)
  { id, }
}

///|
/// Sorted-constructor enum: `First` = 0, `Second` = 1; `Third` is transient
/// (consumes no constructor id, cannot be serialized).
#derive(Debug, Eq)
enum ListElement2 {
  First(ListElement1)
  Second(Uuid, String?, String?)
  Third(String)
}

///|
let second_case_metadata : AdtMetadata = AdtMetadata::new([
  InitialVersion,
  FieldMadeTransient("cached"),
])

///|
impl BinarySerializer for ListElement2 with fn serialize(self, ctx) {
  let writer = AdtWriter::new_v0(list_element2_metadata, ctx)
  let constructor_idx : UInt32 = match self {
    First(_) => 0U
    Second(_, _, _) => 1U
    Third(_) => raise SerializingTransientConstructor("ListElement2.Third")
  }
  writer.write_constructor(constructor_idx, inner => {
    match self {
      First(elem) => {
        let case_writer = AdtWriter::new_v0(list_element1_metadata, inner)
        case_writer.write_field("elem", elem)
        case_writer.finish()
      }
      Second(uuid, desc, _cached) => {
        // `cached` is transient (removed from the wire by
        // FieldMadeTransient); it contributes no bytes.
        let case_writer = AdtWriter::new(second_case_metadata, inner)
        case_writer.write_field("uuid", uuid)
        case_writer.write_field("desc", desc)
        case_writer.finish()
      }
      Third(_) => raise SerializingTransientConstructor("ListElement2.Third")
    }
  })
  writer.finish()
}

///|
let list_element2_metadata : AdtMetadata = AdtMetadata::new([InitialVersion])

///|
fn ListElement2::deserialize_second(
  ctx : DeserializationContext,
) -> ListElement2 raise DesertFailure {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(second_case_metadata, ctx)
  } else {
    AdtReader::new(second_case_metadata, ctx, stored)
  }
  let uuid : Uuid = reader.read_field("uuid", None)
  let desc : String? = reader.read_optional_field("desc", None)
  // `cached` was made transient: never present in the data.
  Second(uuid, desc, None)
}

///|
impl BinaryDeserializer for ListElement2 with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(list_element2_metadata, ctx)
  } else {
    AdtReader::new(list_element2_metadata, ctx, stored)
  }
  let constructor_idx = reader.read_constructor_idx()
  match constructor_idx {
    0 => {
      let _case_version = ctx.read_u8()
      First(BinaryDeserializer::deserialize(ctx))
    }
    1 => ListElement2::deserialize_second(ctx)
    other => raise InvalidConstructorId(other, "ListElement2")
  }
}

///|
/// The golden model: version 3 (three evolution steps).
#derive(Debug)
struct GoldenModel {
  byte : Byte
  short : ShortWire
  int : Int32
  long : Int64
  float : Float
  double : Double
  boolean : Bool
  unit : Unit
  string : String
  uuid : Uuid
  exception : PersistedThrowable
  list : Array[ListElement1]
  array : Array[Int64]
  vector : Array[ListElement1]
  set : @hashset.HashSet[String]
  either : Result[Bool, String]
  tried : Result[ListElement2, PersistedThrowable]
  option : @hashmap.HashMap[String, ListElement2]?
}

///|
let golden_metadata : AdtMetadata = AdtMetadata::new([
  InitialVersion,
  FieldMadeOptional("option"),
  FieldAdded("string"),
  FieldAdded("set"),
])

///|
impl BinarySerializer for GoldenModel with fn serialize(self, ctx) {
  let writer = AdtWriter::new(golden_metadata, ctx)
  writer.write_field("byte", self.byte)
  writer.write_field("short", self.short)
  writer.write_field("int", self.int)
  writer.write_field("long", self.long)
  writer.write_field("float", self.float)
  writer.write_field("double", self.double)
  writer.write_field("boolean", self.boolean)
  writer.write_field("unit", self.unit)
  writer.write_field("string", self.string)
  writer.write_field("uuid", self.uuid)
  writer.write_field("exception", self.exception)
  writer.write_field("list", self.list)
  writer.write_field("array", self.array)
  writer.write_field("vector", self.vector)
  writer.write_field("set", self.set)
  writer.write_field("either", self.either)
  writer.write_field("tried", self.tried)
  writer.write_field("option", self.option)
  writer.finish()
}

///|
impl BinaryDeserializer for GoldenModel with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(golden_metadata, ctx)
  } else {
    AdtReader::new(golden_metadata, ctx, stored)
  }
  let byte = reader.read_field("byte", None)
  let short = reader.read_field("short", None)
  let int = reader.read_field("int", None)
  let long = reader.read_field("long", None)
  let float = reader.read_field("float", None)
  let double = reader.read_field("double", None)
  let boolean = reader.read_field("boolean", None)
  let unit = reader.read_field("unit", None)
  let string = reader.read_field("string", Some("default string"))
  let uuid = reader.read_field("uuid", None)
  let exception = reader.read_field("exception", None)
  let list = reader.read_field("list", None)
  let array = reader.read_field("array", None)
  let vector = reader.read_field("vector", None)
  let set = reader.read_field("set", Some(@hashset.HashSet([])))
  let either = reader.read_field("either", None)
  let tried = reader.read_field("tried", None)
  let option = reader.read_optional_field("option", None)
  {
    byte,
    short,
    int,
    long,
    float,
    double,
    boolean,
    unit,
    string,
    uuid,
    exception,
    list,
    array,
    vector,
    set,
    either,
    tried,
    option,
  }
}

///|
test "golden dataset from desert-scala deserializes and round-trips" {
  let data = golden_dataset1()
  assert_eq(data.length(), 242540)
  let value : GoldenModel = deser_evolved(data)

  // Scalars
  assert_eq(value.byte, (-10).to_byte())
  assert_eq(value.short.value, 10000)
  assert_eq(value.int, -2000000000)
  assert_eq(value.long, 100000000001L)
  assert_eq(value.float, 3.14)
  assert_eq(value.double, 0.1234e-10)
  assert_eq(value.boolean, false)
  assert_eq(value.string, "Example data set")
  assert_eq(value.uuid, Uuid::parse("d90c4285-544d-424d-885c-3940fe00883d"))

  // Exception with nested cause (16 + 16 stack frames)
  assert_eq(value.exception.class_name, "java.lang.RuntimeException")
  assert_eq(value.exception.message, "Example exception")
  assert_eq(value.exception.stack_trace.length(), 16)
  assert_eq(
    value.exception.stack_trace[0].class_name,
    Some("io.github.vigoo.desert.golden.TestModel1$"),
  )
  assert_eq(value.exception.stack_trace[0].line_number, 67)
  let cause = match value.exception.cause {
    Some(c) => c
    None => abort("expected cause")
  }
  assert_eq(cause.class_name, "java.lang.IllegalArgumentException")
  assert_eq(cause.message, "param should not be negative")
  assert_eq(cause.stack_trace.length(), 16)
  assert_eq(cause.cause, None)

  // Collections
  assert_eq(value.list, [{ id: "a", }, { id: "aa", }, { id: "aaa", }])
  assert_eq(value.array.length(), 30000)
  for i in 0..<30000 {
    assert_eq(value.array[i], (i + 1).to_int64())
  }
  assert_eq(value.vector.length(), 100)
  assert_eq(value.vector[0].id, "1")
  assert_eq(value.vector[99].id, "100")
  assert_eq(value.set.contains("hello"), true)
  assert_eq(value.set.contains("world"), true)
  assert_eq(value.set.length(), 2)
  assert_eq(value.either, Ok(true))
  match value.tried {
    Ok(First(elem)) => assert_eq(elem.id, "")
    _ => abort("expected tried = Ok(First)")
  }

  // Option[HashMap[String, ListElement2]] — present, 3 entries
  let map = match value.option {
    Some(m) => m
    None => abort("expected option = Some")
  }
  assert_eq(map.length(), 3)
  match map.get("first") {
    Some(First(elem)) => assert_eq(elem.id, "1st")
    _ => abort("unexpected first case")
  }
  match map.get("second") {
    Some(Second(uuid, desc, _)) => {
      assert_eq(uuid, Uuid::parse("0ca26648-edee-4a2d-bd88-eebf92d19c30"))
      assert_eq(desc, None)
    }
    _ => abort("unexpected second case")
  }
  match map.get("third") {
    Some(Second(uuid, desc, _)) => {
      assert_eq(uuid, Uuid::parse("0ca26648-edee-4a2d-bd88-eebf92d19c30"))
      assert_eq(desc, Some("some description"))
    }
    _ => abort("unexpected third case")
  }

  // Round-trip: our own serialization parses back to the same value.
  let reserialized = ser_evolved(value)
  let again : GoldenModel = deser_evolved(reserialized)
  assert_eq(again.byte, value.byte)
  assert_eq(again.string, value.string)
  assert_eq(again.uuid, value.uuid)
  assert_eq(again.exception.message, value.exception.message)
  assert_eq(again.exception.stack_trace.length(), 16)
  assert_eq(again.array.length(), 30000)
  assert_eq(again.set.length(), 2)
  match again.tried {
    Ok(First(elem)) => assert_eq(elem.id, "")
    _ => abort("roundtrip tried mismatch")
  }
  let again_map = match again.option {
    Some(m) => m
    None => abort("roundtrip option = None")
  }
  assert_eq(again_map.length(), 3)
}

///|
pub extend Uuid with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Uuid with Eq::{not_equal, equal}

///|

///|
pub extend ShortWire with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ShortWire with Eq::{not_equal, equal}

///|

///|
pub extend StackFrame with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend StackFrame with Eq::{not_equal, equal}

///|

///|
pub extend PersistedThrowable with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PersistedThrowable with Eq::{not_equal, equal}

///|
pub extend GoldenModel with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ListElement1 with Eq::{not_equal, equal}

///|
pub extend ListElement1 with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ListElement2 with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ListElement2 with Eq::{not_equal, equal}

///|
test "transient constructor cannot be serialized" {
  let res : Result[Bytes, DesertFailure] = Ok(
    serialize_to_bytes(Third("anything")),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(SerializingTransientConstructor("ListElement2.Third")) => ()
    Err(other) =>
      abort("expected SerializingTransientConstructor, got \{other}")
    Ok(_) => abort("expected a failure")
  }
  // and it consumes no constructor id: reading id 2 fails
  let res2 : Result[ListElement2, DesertFailure] = Ok(
    deserialize_exhaustive(b"\x00\x02\x00"),
  ) catch {
    e => Err(e)
  }
  match res2 {
    Err(InvalidConstructorId(2, "ListElement2")) => ()
    Err(other) => abort("expected InvalidConstructorId 2, got \{other}")
    Ok(_) => abort("expected a failure")
  }
}
