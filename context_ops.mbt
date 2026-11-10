///|
/// The serialization context is itself a `BinaryOutput`: codec code can call
/// `ctx.write_u8(...)`, `ctx.write_var_i32(...)` etc. directly, delegating to
/// the underlying sink (mirrors desert-rust, where the context implements
/// `BinaryOutput`).
impl BinaryOutput for SerializationContext with fn write_u8(self, byte) {
  self.output.write_u8(byte)
}

///|
impl BinaryOutput for SerializationContext with fn write_bytes(self, bytes) {
  self.output.write_bytes(bytes)
}

///|
impl BinaryOutput for SerializationContext with fn write_i8(self, value) {
  self.output.write_i8(value)
}

///|
impl BinaryOutput for SerializationContext with fn write_u16(self, value) {
  self.output.write_u16(value)
}

///|
impl BinaryOutput for SerializationContext with fn write_i16(self, value) {
  self.output.write_i16(value)
}

///|
impl BinaryOutput for SerializationContext with fn write_u32(self, value) {
  self.output.write_u32(value)
}

///|
impl BinaryOutput for SerializationContext with fn write_i32(self, value) {
  self.output.write_i32(value)
}

///|
impl BinaryOutput for SerializationContext with fn write_u64(self, value) {
  self.output.write_u64(value)
}

///|
impl BinaryOutput for SerializationContext with fn write_i64(self, value) {
  self.output.write_i64(value)
}

///|
impl BinaryOutput for SerializationContext with fn write_f32(self, value) {
  self.output.write_f32(value)
}

///|
impl BinaryOutput for SerializationContext with fn write_f64(self, value) {
  self.output.write_f64(value)
}

///|
impl BinaryOutput for SerializationContext with fn write_var_u32(self, value) {
  self.output.write_var_u32(value)
}

///|
impl BinaryOutput for SerializationContext with fn write_var_i32(self, value) {
  self.output.write_var_i32(value)
}

///|
/// Write a UTF-8 encoded string payload: `var_i32(byte_length)` followed by
/// the UTF-8 bytes. This is the primitive used by the `String` codec and by
/// the evolution machinery for field names.
pub fn SerializationContext::write_string_payload(
  self : SerializationContext,
  s : String,
) -> Unit raise DesertFailure {
  let byte_len = utf8_byte_length(s)
  self.write_var_i32(byte_len)
  if byte_len > 0 {
    // Measured fastest: bulk transcode into an exact-size scratch array +
    // one blit. Core's per-char write_string_utf8 loses (branchy loop with
    // grow checks per char); returning a scan struct also regresses (extra
    // GC allocation per call). See OPTIMIZATION_PLAN.md finding F10.
    let scratch = FixedArray::make(byte_len, b'\x00')
    let _ = write_utf8(s, scratch, 0)
    self.write_bytes(Bytes::from_array(scratch).exact_view(end=byte_len))
  }
}

///|
/// The deserialization context exposes the raw read operations of its
/// `BinaryInput` directly, so codec code reads like desert-rust:
/// `ctx.read_u8(...)`, `ctx.read_var_i32(...)` etc.

///|
pub fn DeserializationContext::read_u8(
  self : DeserializationContext,
) -> Byte raise DesertFailure {
  self.input.read_u8()
}

///|
pub fn DeserializationContext::read_bytes_view(
  self : DeserializationContext,
  count : Int32,
) -> BytesView raise DesertFailure {
  self.input.read_bytes_view(count)
}

///|
pub fn DeserializationContext::read_bytes(
  self : DeserializationContext,
  count : Int32,
) -> Bytes raise DesertFailure {
  self.input.read_bytes(count)
}

///|
pub fn DeserializationContext::read_i8(
  self : DeserializationContext,
) -> Int32 raise DesertFailure {
  self.input.read_i8()
}

///|
pub fn DeserializationContext::read_u16(
  self : DeserializationContext,
) -> UInt16 raise DesertFailure {
  self.input.read_u16()
}

///|
pub fn DeserializationContext::read_i16(
  self : DeserializationContext,
) -> Int32 raise DesertFailure {
  self.input.read_i16()
}

///|
pub fn DeserializationContext::read_u32(
  self : DeserializationContext,
) -> UInt32 raise DesertFailure {
  self.input.read_u32()
}

///|
pub fn DeserializationContext::read_i32(
  self : DeserializationContext,
) -> Int32 raise DesertFailure {
  self.input.read_i32()
}

///|
pub fn DeserializationContext::read_u64(
  self : DeserializationContext,
) -> UInt64 raise DesertFailure {
  self.input.read_u64()
}

///|
pub fn DeserializationContext::read_i64(
  self : DeserializationContext,
) -> Int64 raise DesertFailure {
  self.input.read_i64()
}

///|
pub fn DeserializationContext::read_f32(
  self : DeserializationContext,
) -> Float raise DesertFailure {
  self.input.read_f32()
}

///|
pub fn DeserializationContext::read_f64(
  self : DeserializationContext,
) -> Double raise DesertFailure {
  self.input.read_f64()
}

///|
pub fn DeserializationContext::read_var_u32(
  self : DeserializationContext,
) -> UInt32 raise DesertFailure {
  self.input.read_var_u32()
}

///|
pub fn DeserializationContext::read_var_i32(
  self : DeserializationContext,
) -> Int32 raise DesertFailure {
  self.input.read_var_i32()
}

///|
/// Read a UTF-8 encoded string payload (symmetric with
/// `write_string_payload`).
pub fn DeserializationContext::read_string_payload(
  self : DeserializationContext,
) -> String raise DesertFailure {
  let byte_len = self.read_var_i32()
  if byte_len < 0 {
    raise DeserializationFailure("Negative string length")
  }
  if byte_len == 0 {
    return ""
  }
  let view = self.input.read_bytes_view(byte_len)
  read_utf8(view)
}

///|
/// Promote the `BinaryOutput` operations to regular methods, so codecs can
/// write `ctx.write_u8(...)` fluently.
pub extend SerializationContext with BinaryOutput::{
  write_u8,
  write_string_utf8,
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
}

///|
/// Reroute subsequent writes into `output`, saving the previous sink on the
/// context's stack (used by the evolution machinery to capture a record's
/// fields into per-generation chunk buffers).
pub fn SerializationContext::push_output(
  self : SerializationContext,
  output : &BinaryOutput,
) -> Unit {
  let prev = self.output
  self.output_stack.push(prev)
  self.output = output
}

///|
/// Restore the previous output sink, returning the one that was active.
pub fn SerializationContext::pop_output(
  self : SerializationContext,
) -> &BinaryOutput {
  let current = self.output
  match self.output_stack.pop() {
    Some(prev) => self.output = prev
    None => ()
  }
  current
}

///|
/// Position of the input cursor.
pub fn DeserializationContext::pos(self : DeserializationContext) -> Int32 {
  self.input.position()
}

///|
/// Advance the input cursor by `count` bytes (no data is returned).
pub fn DeserializationContext::skip(
  self : DeserializationContext,
  count : Int32,
) -> Unit raise DesertFailure {
  self.input.skip_bytes(count)
}

///|
/// Fence subsequent reads into `region`: the cursor jumps to the region's
/// start and reads beyond its end fail. The previous cursor state is saved.
pub fn DeserializationContext::push_region(
  self : DeserializationContext,
  start : Int32,
  size : Int32,
) -> Unit {
  self.input.push_region(start, size)
}

///|
/// End the current region, restoring the previous cursor state and returning
/// the region's remaining unread range (the caller stores it to continue the
/// chunk later).
pub fn DeserializationContext::pop_region(
  self : DeserializationContext,
) -> (Int32, Int32) {
  self.input.pop_region()
}

///|
/// Read an `Option[T]` payload (tag byte + optional value). Helper for the
/// evolution machinery and derived codecs.
pub fn[T : BinaryDeserializer] DeserializationContext::read_optional_value(
  self : DeserializationContext,
) -> T? raise DesertFailure {
  let _probe : T? = None
  BinaryDeserializer::deserialize(self)
}
