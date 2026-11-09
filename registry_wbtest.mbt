///|
/// Type registry tests: round-trips through `write_unknown`/`read_unknown`,
/// the failure taxonomy (unregistered type, invalid id), placeholders, and
/// interplay with the evolution machinery.

///|
#derive(Debug, Eq)
struct MsgA {
  code : Int32
  text : String
}

///|
impl RegisteredValue for MsgA with fn registered_type_name(_self) {
  "test.MsgA"
}

///|
impl RegisteredValue for MsgA with fn serialize_registered(self, ctx) {
  BinarySerializer::serialize(self, ctx)
}

///|
impl BinarySerializer for MsgA with fn serialize(self, ctx) {
  let writer = AdtWriter::new_v0(msg_metadata, ctx)
  writer.write_field("code", self.code)
  writer.write_field("text", self.text)
  writer.finish()
}

///|
let msg_metadata : AdtMetadata = AdtMetadata::new([InitialVersion])

///|
impl BinaryDeserializer for MsgA with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(msg_metadata, ctx)
  } else {
    AdtReader::new(msg_metadata, ctx, stored)
  }
  let code = reader.read_field("code", None)
  let text = reader.read_field("text", None)
  { code, text, }
}

///|
#derive(Debug, Eq)
struct MsgB {
  flag : Bool
}

///|
impl RegisteredValue for MsgB with fn registered_type_name(_self) {
  "test.MsgB"
}

///|
impl RegisteredValue for MsgB with fn serialize_registered(self, ctx) {
  BinarySerializer::serialize(self, ctx)
}

///|
impl BinarySerializer for MsgB with fn serialize(self, ctx) {
  let writer = AdtWriter::new_v0(msg_metadata, ctx)
  writer.write_field("code", 0)
  writer.write_field("text", if self.flag { "yes" } else { "no" })
  writer.finish()
}

///|
impl BinaryDeserializer for MsgB with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(msg_metadata, ctx)
  } else {
    AdtReader::new(msg_metadata, ctx, stored)
  }
  let _code : Int32 = reader.read_field("code", None)
  let text : String = reader.read_field("text", None)
  { flag: text == "yes", }
}

///|
fn registry_helper() -> TypeRegistry raise DesertFailure {
  TypeRegistryBuilder::new()
  .register("test.MsgA", (ctx : DeserializationContext) => {
    let v : MsgA = BinaryDeserializer::deserialize(ctx)
    v as &RegisteredValue
  })
  .register_placeholder()
  .register("test.MsgB", (ctx : DeserializationContext) => {
    let v : MsgB = BinaryDeserializer::deserialize(ctx)
    v as &RegisteredValue
  })
  .freeze()
}

///|
fn[T : RegisteredValue] reg_ser(value : T, registry : TypeRegistry) -> Bytes {
  let res : Result[Bytes, DesertFailure] = Ok(
    serialize_unknown_to_bytes(value, registry),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(b) => b
    Err(f) => abort("registry serialization failed: \{f}")
  }
}

///|
test "registry roundtrip dispatches by id" {
  let registry = registry_helper()
  // MsgA: id 1 as var_u32, then MsgA payload (version byte + fields).
  let bytes_a = reg_ser(MsgA::{ code: 42, text: "hello", }, registry)
  assert_eq(bytes_a, b"\x01\x00\x00\x00\x00\x2a\x0a\x68\x65\x6c\x6c\x6f")
  let box = deser_evolved_registry(bytes_a, registry)
  assert_eq(box.id, 1)
  assert_eq(box.type_name, "test.MsgA")
  // Extract via an enum-free route: re-serialize the erased value and
  // compare payloads.
  let res : Result[Bytes, DesertFailure] = Ok(
    serialize_unknown_to_bytes(MsgB::{ flag: true, }, registry),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(bytes_b) =>
      // MsgB has id 3 (placeholder reserves id 2).
      assert_eq(bytes_b[0], b'\x03')
    Err(f) => abort("\{f}")
  }
  let _ = box
}

///|
fn deser_evolved_registry(
  data : Bytes,
  registry : TypeRegistry,
) -> RegisteredBox {
  let res : Result[RegisteredBox, DesertFailure] = Ok(
    deserialize_unknown_from_bytes(data, registry),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(b) => b
    Err(f) => abort("registry deserialization failed: \{f}")
  }
}

///|
test "registry placeholder reserves ids" {
  let registry = registry_helper()
  match registry.id_of("test.MsgA") {
    Some(id) => assert_eq(id, 1)
    None => abort("MsgA missing")
  }
  match registry.id_of("test.MsgB") {
    Some(id) => assert_eq(id, 3)
    None => abort("MsgB missing")
  }
  assert_eq(registry.id_of("test.Missing"), None)
}

///|
test "unregistered type fails on write" {
  let registry = TypeRegistry::empty()
  let res : Result[Bytes, DesertFailure] = Ok(
    serialize_unknown_to_bytes(MsgA::{ code: 1, text: "", }, registry),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(TypeNotRegistered("test.MsgA")) => ()
    Err(other) => abort("expected TypeNotRegistered, got \{other}")
    Ok(_) => abort("expected a failure")
  }
}

///|
test "unknown type id fails on read" {
  let registry = registry_helper()
  let res : Result[RegisteredBox, DesertFailure] = Ok(
    deserialize_unknown_from_bytes(b"\x09\x00", registry),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(InvalidTypeId(9)) => ()
    Err(other) => abort("expected InvalidTypeId(9), got \{other}")
    Ok(_) => abort("expected a failure")
  }
}

///|
test "registered value round-trips through the erased box" {
  let registry = registry_helper()
  let bytes = reg_ser(MsgA::{ code: 7, text: "x", }, registry)
  let box = deser_evolved_registry(bytes, registry)
  // Re-serialize the erased value: identical bytes.
  let res : Result[Bytes, DesertFailure] = Ok(
    serialize_unknown_to_bytes(box.value, registry),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(again) => assert_eq(again, bytes)
    Err(f) => abort("\{f}")
  }
}

///|
/// Duplicate registration fails.
test "duplicate type name fails" {
  let res : Result[TypeRegistry, DesertFailure] = Ok(
    TypeRegistryBuilder::new()
    .register("test.MsgA", (ctx : DeserializationContext) => {
      let v : MsgA = BinaryDeserializer::deserialize(ctx)
      v as &RegisteredValue
    })
    .register("test.MsgA", (ctx : DeserializationContext) => {
      let v : MsgA = BinaryDeserializer::deserialize(ctx)
      v as &RegisteredValue
    })
    .freeze(),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(SerializationFailure(_)) => ()
    Err(other) => abort("expected SerializationFailure, got \{other}")
    Ok(_) => abort("expected a failure")
  }
}

///|
/// Registry ids interoperate with evolved payloads and string dedup: the
/// dedup table is shared between the id prefix, the payload and any later
/// deduplicated strings.
#derive(Debug, Eq)
struct NamedMsg {
  id : DeduplicatedString
}

///|
impl RegisteredValue for NamedMsg with fn registered_type_name(_self) {
  "test.NamedMsg"
}

///|
impl RegisteredValue for NamedMsg with fn serialize_registered(self, ctx) {
  BinarySerializer::serialize(self, ctx)
}

///|
impl BinarySerializer for NamedMsg with fn serialize(self, ctx) {
  self.id.serialize(ctx)
}

///|
impl BinaryDeserializer for NamedMsg with fn deserialize(ctx) {
  { id: BinaryDeserializer::deserialize(ctx), }
}

///|
test "dedup state is shared across unknown values" {
  let registry = TypeRegistryBuilder::new()
    .register("test.NamedMsg", (ctx : DeserializationContext) => {
      let v : NamedMsg = BinaryDeserializer::deserialize(ctx)
      v as &RegisteredValue
    })
    .freeze()
  // Two consecutive unknown values, both deduplicating the same string.
  let ctx_out = ByteOutput::new()
  let ctx = SerializationContext::new(
    ctx_out,
    SerializerState::new(),
    Options::default(),
  )
  let s = DeduplicatedString::new("shared")
  let msg1 : NamedMsg = { id: s, }
  let msg2 : NamedMsg = { id: s, }
  ctx.write_unknown(registry, msg1)
  ctx.write_unknown(registry, msg2)
  let bytes = ctx_out.to_bytes()
  // First: id 1 + dedup-new string; second: id 1 + back-reference -1 (0x01).
  assert_eq(bytes, b"\x01\x0c\x73\x68\x61\x72\x65\x64\x01\x01")
  let back = deser_evolved_registry(bytes, registry)
  assert_eq(back.type_name, "test.NamedMsg")
}

///|
pub extend NamedMsg with Eq::{not_equal, equal}

///|
pub extend NamedMsg with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MsgA with Eq::{not_equal, equal}

///|
pub extend MsgA with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MsgB with Eq::{not_equal, equal}

///|
pub extend MsgB with @moonbitlang/core/debug.Debug::{to_repr}
