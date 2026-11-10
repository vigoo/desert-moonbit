///|
/// A byte source the deserializer reads from: an immutable `Bytes` with a
/// mutable cursor. Reads are bounds-checked against the current region limit
/// and fail with `InputEndedUnexpectedly` on underrun.
///
/// The evolution machinery uses `push_region`/`pop_region` to fence reads to
/// a byte range (an evolved record's generation chunk) and `seek` to jump
/// between chunk start positions.
pub struct BinaryInput {
  priv mut data : Bytes
  priv mut pos : Int32
  priv mut limit : Int32
  /// Allocated lazily on first `push_region` — plain version-0
  /// deserialization (the common case) never touches it.
  priv mut region_stack : Array[(Int32, Int32)]?
}

///|
/// Create an input reading from `data`, starting at position 0.
pub fn BinaryInput::new(data : Bytes) -> BinaryInput {
  let len = data.length()
  { data, pos: 0, limit: len, region_stack: None, }
}

///|
/// Number of bytes already consumed.
pub fn BinaryInput::position(self : BinaryInput) -> Int32 {
  self.pos
}

///|
/// Number of bytes left to read.
pub fn BinaryInput::remaining(self : BinaryInput) -> Int32 {
  self.limit - self.pos
}

///|
/// True when the whole input has been consumed.
pub fn BinaryInput::is_empty(self : BinaryInput) -> Bool {
  self.remaining() == 0
}

///|
fn BinaryInput::ensure(
  self : BinaryInput,
  count : Int32,
) -> Unit raise DesertFailure {
  if self.limit - self.pos < count {
    raise InputEndedUnexpectedly
  }
}

///|
/// Move the cursor to an absolute position within the current region.
/// Only used by the evolution machinery to jump to a chunk's start.
pub fn BinaryInput::seek(
  self : BinaryInput,
  target : Int32,
) -> Unit raise DesertFailure {
  if target < 0 || target > self.limit {
    raise InputEndedUnexpectedly
  }
  self.pos = target
}

///|
/// Advance the cursor by `count` bytes; negative counts fail cleanly
/// instead of wrapping into a trap on a later view construction.
pub fn BinaryInput::skip_bytes(
  self : BinaryInput,
  count : Int32,
) -> Unit raise DesertFailure {
  if count < 0 {
    raise DeserializationFailure("Negative skip count: \{count}")
  }
  self.ensure(count)
  self.pos = self.pos + count
}

///|
/// Fence reads into `[start, start + size)`: the cursor jumps to `start`,
/// the region end becomes the read limit, and the previous cursor state is
/// pushed onto the region stack.
pub fn BinaryInput::push_region(
  self : BinaryInput,
  start : Int32,
  size : Int32,
) -> Unit {
  match self.region_stack {
    Some(stack) => stack.push((self.pos, self.limit))
    None => {
      let stack : Array[(Int32, Int32)] = [(self.pos, self.limit)]
      self.region_stack = Some(stack)
    }
  }
  self.pos = start
  self.limit = start + size
}

///|
/// End the current region: restores the previous cursor state and returns
/// the region's remaining `(start, size)` range so the caller can resume the
/// same chunk later.
pub fn BinaryInput::pop_region(self : BinaryInput) -> (Int32, Int32) {
  let remaining_start = self.pos
  let remaining_size = self.limit - self.pos
  match self.region_stack {
    Some(stack) =>
      match stack.pop() {
        Some((pos, limit)) => {
          self.pos = pos
          self.limit = limit
        }
        None => ()
      }
    None => ()
  }
  (remaining_start, remaining_size)
}

///|
/// Read a single raw byte.
pub fn BinaryInput::read_u8(self : BinaryInput) -> Byte raise DesertFailure {
  self.ensure(1)
  let b = self.data[self.pos]
  self.pos = self.pos + 1
  b
}

///|
/// Read `count` raw bytes as a zero-copy view.
pub fn BinaryInput::read_bytes_view(
  self : BinaryInput,
  count : Int32,
) -> BytesView raise DesertFailure {
  if count < 0 {
    raise DeserializationFailure("Negative byte count: \{count}")
  }
  self.ensure(count)
  let view = self.data.exact_view(start=self.pos, end=self.pos + count)
  self.pos = self.pos + count
  view
}

///|
/// Read `count` raw bytes into an owned `Bytes`.
pub fn BinaryInput::read_bytes(
  self : BinaryInput,
  count : Int32,
) -> Bytes raise DesertFailure {
  self.read_bytes_view(count).to_owned()
}

///|
/// Read a 1-byte signed integer, sign-extended into an `Int`.
pub fn BinaryInput::read_i8(self : BinaryInput) -> Int32 raise DesertFailure {
  let v = self.read_u8().to_int()
  if v >= 128 {
    v - 256
  } else {
    v
  }
}

///|
/// Read a 2-byte big-endian unsigned integer.
pub fn BinaryInput::read_u16(self : BinaryInput) -> UInt16 raise DesertFailure {
  self.ensure(2)
  let v = Bytes::unsafe_read_uint16_be(self.data, self.pos)
  self.pos = self.pos + 2
  v
}

///|
/// Read a 2-byte big-endian signed integer, sign-extended into an `Int`.
pub fn BinaryInput::read_i16(self : BinaryInput) -> Int32 raise DesertFailure {
  let v = self.read_u16().to_int()
  if v >= 0x8000 {
    v - 0x10000
  } else {
    v
  }
}

///|
/// Read a 4-byte big-endian unsigned integer.
pub fn BinaryInput::read_u32(self : BinaryInput) -> UInt32 raise DesertFailure {
  self.ensure(4)
  let v = Bytes::unsafe_read_uint32_be(self.data, self.pos)
  self.pos = self.pos + 4
  v
}

///|
/// Read a 4-byte big-endian signed integer.
pub fn BinaryInput::read_i32(self : BinaryInput) -> Int32 raise DesertFailure {
  self.read_u32().reinterpret_as_int()
}

///|
/// Read an 8-byte big-endian unsigned integer.
pub fn BinaryInput::read_u64(self : BinaryInput) -> UInt64 raise DesertFailure {
  self.ensure(8)
  let v = Bytes::unsafe_read_uint64_be(self.data, self.pos)
  self.pos = self.pos + 8
  v
}

///|
/// Read an 8-byte big-endian signed integer.
pub fn BinaryInput::read_i64(self : BinaryInput) -> Int64 raise DesertFailure {
  self.read_u64().reinterpret_as_int64()
}

///|
/// Read a 4-byte IEEE-754 float (big-endian bit pattern).
pub fn BinaryInput::read_f32(self : BinaryInput) -> Float raise DesertFailure {
  Float::reinterpret_from_uint(self.read_u32())
}

///|
/// Read an 8-byte IEEE-754 double (big-endian bit pattern).
pub fn BinaryInput::read_f64(self : BinaryInput) -> Double raise DesertFailure {
  self.read_u64().reinterpret_as_double()
}

///|
/// Read a base-128 varint of an unsigned 32-bit value. Fails with
/// `DeserializationFailure` if the encoding exceeds 5 bytes.
pub fn BinaryInput::read_var_u32(
  self : BinaryInput,
) -> UInt32 raise DesertFailure {
  let mut result = 0U
  let mut shift = 0
  for _i in 0..<5 {
    let byte = self.read_u8().to_uint()
    result = result | ((byte & 0x7F) << shift)
    if byte < 0x80 {
      return result
    }
    shift = shift + 7
  }
  raise DeserializationFailure("var_u32 too long")
}

///|
/// Read a zigzag-mapped signed varint (symmetric with `write_var_i32`).
pub fn BinaryInput::read_var_i32(
  self : BinaryInput,
) -> Int32 raise DesertFailure {
  let raw = self.read_var_u32()
  let inv = if (raw & 1U) == 1U { 0xFFFFFFFFU } else { 0U }
  ((raw >> 1) ^ inv).reinterpret_as_int()
}

///|
/// Point the input at new data and clear any region state, reusing the
/// allocated object. Session state lives in the `DeserializationContext`
/// and is reset separately.
pub fn BinaryInput::reset_input(self : BinaryInput, data : Bytes) -> Unit {
  self.data = data
  self.pos = 0
  self.limit = data.length()
  self.region_stack = None
}
