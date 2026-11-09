///|
/// Primitive codecs.
///
/// Wire encodings (byte-compatible with desert / desert-rust):
/// - `Byte`   : 1 raw byte
/// - `Bool`   : 1 byte, `1` = true, `0` = false
/// - `UInt16` : 2 bytes, big-endian
/// - `Int`    : 4 bytes, big-endian, two's complement
/// - `UInt`   : 4 bytes, big-endian
/// - `Int64`  : 8 bytes, big-endian, two's complement
/// - `UInt64` : 8 bytes, big-endian
/// - `Float`  : 4 bytes, IEEE-754 bits, big-endian
/// - `Double` : 8 bytes, IEEE-754 bits, big-endian
/// - `Unit`   : zero bytes

///|
pub impl BinarySerializer for Byte with fn serialize(self, ctx) {
  ctx.write_u8(self)
}

///|
pub impl BinaryDeserializer for Byte with fn deserialize(ctx) {
  ctx.input.read_u8()
}

///|
pub impl BinarySerializer for Bool with fn serialize(self, ctx) {
  ctx.write_u8(if self { b'\x01' } else { b'\x00' })
}

///|
pub impl BinaryDeserializer for Bool with fn deserialize(ctx) {
  ctx.input.read_u8() != b'\x00'
}

///|
pub impl BinarySerializer for UInt16 with fn serialize(self, ctx) {
  ctx.write_u16(self)
}

///|
pub impl BinaryDeserializer for UInt16 with fn deserialize(ctx) {
  ctx.input.read_u16()
}

///|
pub impl BinarySerializer for Int32 with fn serialize(self, ctx) {
  ctx.write_i32(self)
}

///|
pub impl BinaryDeserializer for Int32 with fn deserialize(ctx) {
  ctx.input.read_i32()
}

///|
pub impl BinarySerializer for UInt32 with fn serialize(self, ctx) {
  ctx.write_u32(self)
}

///|
pub impl BinaryDeserializer for UInt32 with fn deserialize(ctx) {
  ctx.input.read_u32()
}

///|
pub impl BinarySerializer for Int64 with fn serialize(self, ctx) {
  ctx.write_i64(self)
}

///|
pub impl BinaryDeserializer for Int64 with fn deserialize(ctx) {
  ctx.input.read_i64()
}

///|
pub impl BinarySerializer for UInt64 with fn serialize(self, ctx) {
  ctx.write_u64(self)
}

///|
pub impl BinaryDeserializer for UInt64 with fn deserialize(ctx) {
  ctx.input.read_u64()
}

///|
pub impl BinarySerializer for Float with fn serialize(self, ctx) {
  ctx.write_f32(self)
}

///|
pub impl BinaryDeserializer for Float with fn deserialize(ctx) {
  ctx.input.read_f32()
}

///|
pub impl BinarySerializer for Double with fn serialize(self, ctx) {
  ctx.write_f64(self)
}

///|
pub impl BinaryDeserializer for Double with fn deserialize(ctx) {
  ctx.input.read_f64()
}

///|
/// `Unit` occupies zero bytes on the wire.
pub impl BinarySerializer for Unit with fn serialize(_self, _ctx) {

}

///|
pub impl BinaryDeserializer for Unit with fn deserialize(_ctx) {
  ()
}
