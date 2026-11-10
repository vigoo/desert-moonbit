///|
/// A byte sink the serializer writes to.
///
/// Only the two raw operations are required; everything else (fixed-width
/// big-endian primitives, varints, floats) has a default implementation built
/// on them, so any custom sink only has to provide `write_u8` and
/// `write_bytes`. The built-in `ByteOutput` overrides the fixed-width methods
/// with bulk fast paths.
///
/// The wire format is fixed: all fixed-width values are big-endian, varints
/// are LEB128-style base-128 (least-significant 7 bits first, high bit is the
/// continuation bit) with zigzag mapping for the signed variant.
pub(open) trait BinaryOutput {
  /// Write a single raw byte.
  fn write_u8(Self, Byte) -> Unit raise DesertFailure
  /// Write a run of raw bytes.
  fn write_bytes(Self, BytesView) -> Unit raise DesertFailure
  /// Write a 1-byte signed integer (reinterpreted).
  fn write_i8(Self, Int32) -> Unit raise DesertFailure = _
  /// Write a 2-byte big-endian unsigned integer.
  fn write_u16(Self, UInt16) -> Unit raise DesertFailure = _
  /// Write a 2-byte big-endian signed integer.
  fn write_i16(Self, Int32) -> Unit raise DesertFailure = _
  /// Write a 4-byte big-endian unsigned integer.
  fn write_u32(Self, UInt32) -> Unit raise DesertFailure = _
  /// Write a 4-byte big-endian signed integer.
  fn write_i32(Self, Int32) -> Unit raise DesertFailure = _
  /// Write an 8-byte big-endian unsigned integer.
  fn write_u64(Self, UInt64) -> Unit raise DesertFailure = _
  /// Write an 8-byte big-endian signed integer.
  fn write_i64(Self, Int64) -> Unit raise DesertFailure = _
  /// Write a 4-byte IEEE-754 float, big-endian bit pattern.
  fn write_f32(Self, Float) -> Unit raise DesertFailure = _
  /// Write an 8-byte IEEE-754 double, big-endian bit pattern.
  fn write_f64(Self, Double) -> Unit raise DesertFailure = _
  /// Write a base-128 varint of an unsigned 32-bit value (1-5 bytes).
  fn write_var_u32(Self, UInt32) -> Unit raise DesertFailure = _
  /// Write a base-128 varint of a signed 32-bit value, zigzag-mapped
  /// (1-5 bytes, symmetric with `write_var_u32`).
  fn write_var_i32(Self, Int32) -> Unit raise DesertFailure = _
  /// Write a string as UTF-8. The default implementation transcodes into a
  /// scratch buffer and forwards to `write_bytes`; buffer-backed sinks
  /// override it with a zero-allocation pass (lone surrogates are the
  /// caller's responsibility — this operation writes the view as-is).
  fn write_string_utf8(Self, StringView) -> Unit raise DesertFailure = _
}

///|
/// Default `BinaryOutput` implementations, built on `write_u8`.
impl BinaryOutput with fn write_i8(self, value : Int32) {
  self.write_u8(value.to_byte())
}

///|
impl BinaryOutput with fn write_u16(self, value : UInt16) {
  let v = value.to_uint()
  self.write_u8((v >> 8).to_byte())
  self.write_u8(v.to_byte())
}

///|
impl BinaryOutput with fn write_i16(self, value : Int32) {
  self.write_u16((value & 0xFFFF).to_uint16())
}

///|
impl BinaryOutput with fn write_u32(self, value : UInt32) {
  self.write_u8((value >> 24).to_byte())
  self.write_u8(((value >> 16) & 0xFF).to_byte())
  self.write_u8(((value >> 8) & 0xFF).to_byte())
  self.write_u8((value & 0xFF).to_byte())
}

///|
impl BinaryOutput with fn write_i32(self, value : Int32) {
  self.write_u32(value.reinterpret_as_uint())
}

///|
impl BinaryOutput with fn write_u64(self, value : UInt64) {
  let v = value
  self.write_u8((v >> 56).to_byte())
  self.write_u8(((v >> 48) & 0xFFUL).to_byte())
  self.write_u8(((v >> 40) & 0xFFUL).to_byte())
  self.write_u8(((v >> 32) & 0xFFUL).to_byte())
  self.write_u8(((v >> 24) & 0xFFUL).to_byte())
  self.write_u8(((v >> 16) & 0xFFUL).to_byte())
  self.write_u8(((v >> 8) & 0xFFUL).to_byte())
  self.write_u8((v & 0xFFUL).to_byte())
}

///|
impl BinaryOutput with fn write_i64(self, value : Int64) {
  self.write_u64(value.reinterpret_as_uint64())
}

///|
impl BinaryOutput with fn write_f32(self, value : Float) {
  self.write_u32(value.reinterpret_as_uint())
}

///|
impl BinaryOutput with fn write_f64(self, value : Double) {
  self.write_u64(value.reinterpret_as_uint64())
}

///|
impl BinaryOutput with fn write_var_u32(self, value : UInt32) {
  let mut v = value
  while v >= 0x80 {
    self.write_u8(((v & 0x7F) | 0x80).to_byte())
    v = v >> 7
  }
  self.write_u8(v.to_byte())
}

///|
/// Zigzag-mapped signed varint: `(v << 1) ^ (v >> 31)`, matching the Scala
/// `writeVarInt(value, optimizeForPositive = false)` and the Rust
/// `write_var_i32`.
impl BinaryOutput with fn write_var_i32(self, value : Int32) {
  let zigzag = (value << 1) ^ (value >> 31)
  self.write_var_u32(zigzag.reinterpret_as_uint())
}

///|
/// A `BinaryOutput` that accumulates into an in-memory growable byte buffer.
///
/// Overrides the fixed-width operations with the bulk fast paths of the core
/// `Buffer`.
pub struct ByteOutput {
  priv buffer : Buffer
}

///|
/// Create an empty output. Pass `capacity~` to pre-allocate.
pub fn ByteOutput::new(capacity~ : Int32 = 128) -> ByteOutput {
  { buffer: Buffer(size_hint=capacity), }
}

///|
pub impl BinaryOutput for ByteOutput with fn write_u8(self, byte) {
  self.buffer.write_byte(byte)
}

///|
pub impl BinaryOutput for ByteOutput with fn write_bytes(self, bytes) {
  self.buffer.write_bytesview(bytes)
}

///|
pub impl BinaryOutput for ByteOutput with fn write_i16(self, value) {
  self.buffer.write_uint16_be((value & 0xFFFF).to_uint16())
}

///|
pub impl BinaryOutput for ByteOutput with fn write_u16(self, value) {
  self.buffer.write_uint16_be(value)
}

///|
pub impl BinaryOutput for ByteOutput with fn write_i32(self, value) {
  self.buffer.write_int_be(value)
}

///|
pub impl BinaryOutput for ByteOutput with fn write_u32(self, value) {
  self.buffer.write_uint_be(value)
}

///|
pub impl BinaryOutput for ByteOutput with fn write_i64(self, value) {
  self.buffer.write_int64_be(value)
}

///|
pub impl BinaryOutput for ByteOutput with fn write_u64(self, value) {
  self.buffer.write_uint64_be(value)
}

///|
pub impl BinaryOutput for ByteOutput with fn write_f32(self, value) {
  self.buffer.write_float_be(value)
}

///|
pub impl BinaryOutput for ByteOutput with fn write_f64(self, value) {
  self.buffer.write_double_be(value)
}

///|
/// Zero-allocation pass-through to the core Buffer's UTF-8 writer.
pub impl BinaryOutput for ByteOutput with fn write_string_utf8(self, s) {
  self.buffer.write_string_utf8(s)
}

///|
/// The bytes written so far, as an immutable snapshot.
pub fn ByteOutput::to_bytes(self : ByteOutput) -> Bytes {
  self.buffer.to_bytes()
}

///|
/// Number of bytes written so far.
pub fn ByteOutput::length(self : ByteOutput) -> Int32 {
  self.buffer.length()
}

///|
/// Promote the `BinaryOutput` operations to regular methods on `ByteOutput`.
pub extend ByteOutput with BinaryOutput::{
  write_u8,
  write_bytes,
  write_i8,
  write_u16,
  write_i16,
  write_u32,
  write_i32,
  write_u64,
  write_i64,
  write_f32,
  write_f64,
  write_var_u32,
  write_var_i32,
  write_string_utf8,
}

///|
/// Discard the bytes written so far, reusing the allocated capacity.
pub fn ByteOutput::reset(self : ByteOutput) -> Unit {
  self.buffer.reset()
}

///|
/// Default `write_string_utf8`: transcode into a scratch array (exact-size
/// allocation), then bulk-write. Lone surrogates are substituted with `?`.
impl BinaryOutput with fn write_string_utf8(self, s : StringView) {
  let owned = s.to_owned()
  let byte_len = utf8_byte_length(owned)
  if byte_len == 0 {
    return
  }
  let scratch : FixedArray[Byte] = FixedArray::make(byte_len, b'\x00')
  let _ = write_utf8(owned, scratch, 0)
  self.write_bytes(Bytes::from_array(scratch).exact_view(end=byte_len))
}
