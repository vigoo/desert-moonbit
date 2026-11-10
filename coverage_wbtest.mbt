///|
fn[T : BinarySerializer] cser(value : T) -> Bytes {
  let res : Result[Bytes, DesertFailure] = Ok(serialize_to_bytes(value)) catch {
    e => Err(e)
  }
  match res {
    Ok(b) => b
    Err(f) => abort("serialization failed: \{f}")
  }
}

///|
fn[T : BinaryDeserializer] cdeser(data : Bytes) -> T {
  let res : Result[T, DesertFailure] = Ok(deserialize_exhaustive(data)) catch {
    e => Err(e)
  }
  match res {
    Ok(v) => v
    Err(f) => abort("deserialization failed: \{f}")
  }
}

///|
/// Coverage gap-filling tests: error messages for every failure variant,
/// all tuple arities, the BinaryOutput default implementations over a
/// minimal custom sink, context read/write passthroughs, and negative
/// branches of the collection codecs.

///|
test "failure messages cover every variant" {
  let failures : Array[DesertFailure] = [
    FailedToReadInput("r"),
    InputEndedUnexpectedly,
    FailedToWriteOutput("w"),
    SerializationFailure("s"),
    DeserializationFailure("d"),
    DeserializingNonExistingChunk(3),
    NonOptionalFieldSerializedAsNone("f"),
    UnknownFieldReferenceInEvolutionStep("f"),
    UnknownSerializedEvolutionStep(-7),
    InvalidStringId(9),
    FieldRemovedInSerializedVersion("f"),
    FieldWithoutDefaultValueIsMissing("f"),
    TypeNotRegistered("T"),
    InvalidTypeId(5),
    SerializationUpcastError("A", "B", "why"),
    InvalidConstructorName("n", "T"),
    InvalidConstructorId(4, "T"),
    InvalidRefId(2),
    SerializingTransientConstructor("C"),
    UnsupportedCharacter('x'),
    FailedToDecodeCharacter(0xD800),
  ]
  for f in failures {
    // Every variant renders a non-empty message through both APIs.
    let msg = f.message()
    assert_eq(msg.is_empty(), false)
    let shown = Show::to_string(f)
    assert_eq(shown.is_empty(), false)
  }
}

///|
test "tuple arities 3 to 6 roundtrip" {
  let t3 : (Int32, String, Bool) = (1, "b", true)
  assert_eq(cdeser(cser(t3)), t3)
  let t4 : (Int32, String, Bool, Int32) = (1, "b", true, 4)
  assert_eq(cdeser(cser(t4)), t4)
  let t5 : (Int32, Int32, Int32, Int32, Int32) = (1, 2, 3, 4, 5)
  assert_eq(cdeser(cser(t5)), t5)
  let t6 : (Int32, Int32, Int32, Int32, Int32, Int32) = (1, 2, 3, 4, 5, 6)
  assert_eq(cdeser(cser(t6)), t6)
}

///|
/// A minimal custom sink with no overrides exercises every default
/// `BinaryOutput` implementation.
struct RawSink {
  buffer : Buffer
}

///|
fn RawSink::new() -> RawSink {
  { buffer: Buffer(size_hint=64), }
}

///|
impl BinaryOutput for RawSink with fn write_u8(self, byte) {
  self.buffer.write_byte(byte)
}

///|
impl BinaryOutput for RawSink with fn write_bytes(self, bytes) {
  self.buffer.write_bytesview(bytes)
}

///|
test "default BinaryOutput implementations over a minimal sink" {
  let sink = RawSink::new()
  BinaryOutput::write_i8(sink, -1)
  BinaryOutput::write_u16(sink, 0xAABB)
  BinaryOutput::write_i16(sink, -2)
  BinaryOutput::write_u32(sink, 0x01020304U)
  BinaryOutput::write_i32(sink, -1)
  BinaryOutput::write_u64(sink, 0x0102030405060708UL)
  BinaryOutput::write_i64(sink, -1L)
  BinaryOutput::write_f32(sink, 1.5)
  BinaryOutput::write_f64(sink, 1.5)
  BinaryOutput::write_var_u32(sink, 300U)
  BinaryOutput::write_var_i32(sink, -64)
  let bytes = sink.buffer.to_bytes()
  assert_eq(
    bytes, b"\xff\xaa\xbb\xff\xfe\x01\x02\x03\x04\xff\xff\xff\xff\x01\x02\x03\x04\x05\x06\x07\x08\xff\xff\xff\xff\xff\xff\xff\xff\x3f\xc0\x00\x00\x3f\xf8\x00\x00\x00\x00\x00\x00\xac\x02\x7f",
  )
}

///|
test "context write/read passthroughs roundtrip" {
  let out = ByteOutput::new()
  let wctx = SerializationContext::new(
    out,
    SerializerState::new(),
    Options::default(),
  )
  wctx.write_i8(-2)
  wctx.write_u16(0xAABB)
  wctx.write_i16(-2)
  wctx.write_u32(0x01020304U)
  wctx.write_i32(-1)
  wctx.write_u64(0x0102030405060708UL)
  wctx.write_i64(-1L)
  wctx.write_f32(1.5)
  wctx.write_f64(1.5)
  wctx.write_var_u32(300U)
  wctx.write_var_i32(-64)
  let data = out.to_bytes()
  let rctx = DeserializationContext::new(
    BinaryInput::new(data),
    SerializerState::new(),
    Options::default(),
  )
  assert_eq(rctx.read_i8(), -2)
  assert_eq(rctx.read_u16(), 0xAABB)
  assert_eq(rctx.read_i16(), -2)
  assert_eq(rctx.read_u32(), 0x01020304U)
  assert_eq(rctx.read_i32(), -1)
  assert_eq(rctx.read_u64(), 0x0102030405060708UL)
  assert_eq(rctx.read_i64(), -1L)
  assert_eq(rctx.read_f32(), 1.5)
  assert_eq(rctx.read_f64(), 1.5)
  assert_eq(rctx.read_var_u32(), 300U)
  assert_eq(rctx.read_var_i32(), -64)
}

///|

///|
fn expect_fail_opt(data : Bytes) -> DesertFailure {
  let ctx = DeserializationContext::new(
    BinaryInput::new(data),
    SerializerState::new(),
    Options::default(),
  )
  let res : Result[Int32?, DesertFailure] = Ok(
    BinaryDeserializer::deserialize(ctx),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(f) => f
    Ok(_) => abort("expected a failure")
  }
}

///|
fn expect_fail_result(data : Bytes) -> DesertFailure {
  let ctx = DeserializationContext::new(
    BinaryInput::new(data),
    SerializerState::new(),
    Options::default(),
  )
  let res : Result[Result[Int32, String], DesertFailure] = Ok(
    BinaryDeserializer::deserialize(ctx),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(f) => f
    Ok(_) => abort("expected a failure")
  }
}

///|
fn expect_fail_array(data : Bytes) -> DesertFailure {
  let ctx = DeserializationContext::new(
    BinaryInput::new(data),
    SerializerState::new(),
    Options::default(),
  )
  let res : Result[Array[Int32], DesertFailure] = Ok(
    BinaryDeserializer::deserialize(ctx),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(f) => f
    Ok(_) => abort("expected a failure")
  }
}

///|
fn expect_fail_map(data : Bytes) -> DesertFailure {
  let ctx = DeserializationContext::new(
    BinaryInput::new(data),
    SerializerState::new(),
    Options::default(),
  )
  let res : Result[Map[String, Int32], DesertFailure] = Ok(
    BinaryDeserializer::deserialize(ctx),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(f) => f
    Ok(_) => abort("expected a failure")
  }
}

///|
test "negative branches of option/result/collection tags" {
  // Wrong Option tag
  match expect_fail_opt(b"\x02") {
    DeserializationFailure(_) => ()
    _ => abort("expected DeserializationFailure")
  }
  // Wrong Result tag
  match expect_fail_result(b"\x02") {
    DeserializationFailure(_) => ()
    _ => abort("expected DeserializationFailure")
  }
  // Negative collection length
  match expect_fail_array(b"\x03") {
    DeserializationFailure(_) => ()
    _ => abort("expected DeserializationFailure")
  }
  // Invalid unknown-size element tag
  match expect_fail_array(b"\x01\x05") {
    DeserializationFailure(_) => ()
    _ => abort("expected DeserializationFailure")
  }
  // HashMap negative length
  match expect_fail_map(b"\x03") {
    DeserializationFailure(_) => ()
    _ => abort("expected DeserializationFailure")
  }
}

///|
test "facade serialize_to_output and deserialize with options" {
  let out = ByteOutput::new()
  serialize_to_output('A', out, options=Options::scala_compatible())
  assert_eq(out.to_bytes(), b"\x00\x41")
  let back : Char = deserialize(
    out.to_bytes(),
    options=Options::scala_compatible(),
  )
  assert_eq(back, 'A')
}

///|
test "unsupported char in scala mode and decode failure" {
  let res : Result[Bytes, DesertFailure] = Ok(
    serialize_to_bytes('😀', options=Options::scala_compatible()),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(UnsupportedCharacter(_)) => ()
    _ => abort("expected UnsupportedCharacter")
  }
  // Deserializing a lone surrogate unit fails in scala mode.
  let res2 : Result[Char, DesertFailure] = Ok(
    deserialize_exhaustive(b"\xd8\x3d", options=Options::scala_compatible()),
  ) catch {
    e => Err(e)
  }
  match res2 {
    Err(FailedToDecodeCharacter(0xD83D)) => ()
    _ => abort("expected FailedToDecodeCharacter")
  }
}

///|
test "dedup back-reference to unknown id fails" {
  let res : Result[DeduplicatedString, DesertFailure] = Ok(
    deserialize_exhaustive(b"\x01"),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(InvalidStringId(1)) => ()
    _ => abort("expected InvalidStringId(1)")
  }
}

///|
test "map and hashset roundtrips" {
  let map : Map[String, Int32] = { "a": 1, "b": 2 }
  let back : Map[String, Int32] = cdeser(cser(map))
  assert_eq(back.length(), 2)
  assert_eq(back.get("a"), Some(1))
  assert_eq(back.get("b"), Some(2))
  let set : @hashset.HashSet[String] = @hashset.HashSet(["x", "y"])
  let set_back : @hashset.HashSet[String] = cdeser(cser(set))
  assert_eq(set_back.length(), 2)
  assert_eq(set_back.contains("x"), true)
  assert_eq(set_back.contains("y"), true)
}

///|
test "compressed block validation" {
  // Uncompressed 255 (0xff 0x01 varint), compressed 0: empty data block.
  let data : Bytes = b"\xff\x01\x00"
  let res : Result[Bytes, DesertFailure] = Ok(decompress_bytes(data)) catch {
    e => Err(e)
  }
  match res {
    Err(
      DeserializationFailure(
        "Empty compressed block with non-zero uncompressed length"
      )
    ) => ()
    _ => abort("expected empty-block failure")
  }
  // Empty compressed block with non-zero uncompressed length fails.
  let bad : Bytes = b"\x04\x00"
  let res2 : Result[Bytes, DesertFailure] = Ok(decompress_bytes(bad)) catch {
    e => Err(e)
  }
  match res2 {
    Err(
      DeserializationFailure(
        "Empty compressed block with non-zero uncompressed length"
      )
    ) => ()
    _ => abort("expected empty-block failure")
  }
}

///|
test "input seek and remaining" {
  let input = BinaryInput::new(b"\x01\x02\x03\x04")
  assert_eq(input.remaining(), 4)
  input.seek(2)
  assert_eq(input.position(), 2)
  assert_eq(input.remaining(), 2)
  assert_eq(input.read_u8(), b'\x03')
  // Out-of-range seek fails.
  let res : Result[Unit, DesertFailure] = Ok(input.seek(10)) catch {
    e => Err(e)
  }
  match res {
    Err(InputEndedUnexpectedly) => ()
    _ => abort("expected InputEndedUnexpectedly")
  }
}

///|
test "Int16 codec: wire format, sign handling, roundtrip" {
  // Wire: 2-byte BE two's complement (matches Scala Short / Rust i16).
  let v = Int16::reinterpret_from_uint16((0x10000 - 1234).to_uint16())
  assert_eq(cser(v), b"\xfb\x2e")
  let back : Int16 = cdeser(b"\xfb\x2e")
  assert_eq(back.to_int(), -1234)
  // Roundtrip extremes via the public codec.
  let lo : Int16 = Int16::reinterpret_from_uint16((0x8000).to_uint16())
  let lo_back : Int16 = cdeser(cser(lo))
  assert_eq(lo_back.to_int(), -32768)
  let hi : Int16 = Int16::reinterpret_from_uint16((0x7FFF).to_uint16())
  let hi_back : Int16 = cdeser(cser(hi))
  assert_eq(hi_back.to_int(), 32767)
}

///|
test "Bytes codec rejects negative (2^31) length cleanly" {
  // var_u32(2147483648) — reinterprets as negative Int32; must fail with
  // DesertFailure instead of trapping in view construction.
  let hostile : Bytes = b"\x80\x80\x80\x80\x08\x01\x02\x03\x04"
  let res : Result[Bytes, DesertFailure] = Ok(deserialize_exhaustive(hostile)) catch {
    e => Err(e)
  }
  match res {
    Err(DeserializationFailure(_)) => ()
    _ => abort("expected a clean DeserializationFailure")
  }
}

///|
test "Char decode rejects invalid code points" {
  // Raw-varint Char inputs (default encoding = raw varint code point).
  fn char_bytes(cp : UInt32) -> Bytes raise DesertFailure {
    let out = ByteOutput::new()
    let ctx = SerializationContext::new(
      out,
      SerializerState::new(),
      Options::default(),
    )
    ctx.write_var_u32(cp)
    out.to_bytes()
  }

  fn decode_char(bytes : Bytes) -> Result[Char, DesertFailure] {
    let res : Result[Char, DesertFailure] = Ok(deserialize_exhaustive(bytes)) catch {
      e => Err(e)
    }
    res
  }

  fn expect_fail(bytes : Bytes) -> Unit {
    match decode_char(bytes) {
      Err(DeserializationFailure(_)) => ()
      _ => abort("expected a clean DeserializationFailure")
    }
  }

  // Code point 0x110000 (beyond Unicode max).
  expect_fail(char_bytes(0x110000))
  // Surrogate code point 0xD800.
  expect_fail(char_bytes(0xD800))
  // A value whose reinterpret_as_int is negative.
  expect_fail(char_bytes(0xFFFFFFFF))
  // Valid boundary values still decode (raw varints).
  assert_eq(
    match decode_char(char_bytes(0)) {
      Ok(c) => c.to_int()
      Err(_) => -1
    },
    0,
  )
  assert_eq(
    match decode_char(char_bytes(0x10FFFF)) {
      Ok(c) => c.to_int()
      Err(_) => -1
    },
    0x10FFFF,
  )
}
