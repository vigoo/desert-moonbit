///|
fn[T : @desert.BinarySerializer + @desert.BinaryDeserializer] rt(v : T) -> T {
  let data = ser(v)
  let res : Result[T, @desert.DesertFailure] = Ok(
    @desert.deserialize_exhaustive(data),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(x) => x
    Err(f) => abort("roundtrip failed: \{f}")
  }
}

///|
/// Byte-exact wire-format tests. The expected byte sequences are the
/// verified cross-language dumps: every byte here was produced by both the
/// original Scala library and desert-rust, so these tests pin
/// cross-implementation wire compatibility.

///|
fn[T : @desert.BinarySerializer] ser(value : T) -> Bytes {
  let res : Result[Bytes, @desert.DesertFailure] = Ok(
    @desert.serialize_to_bytes(value),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(b) => b
    Err(f) => abort("serialization failed: \{f}")
  }
}

///|
fn[T : @desert.BinaryDeserializer] deser(data : Bytes) -> T {
  let res : Result[T, @desert.DesertFailure] = Ok(
    @desert.deserialize_exhaustive(data),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(v) => v
    Err(f) => abort("deserialization failed: \{f}")
  }
}

///|
test "i32 fixed width big endian" {
  assert_eq(ser(42), b"\x00\x00\x00\x2a")
  assert_eq(ser(-10), b"\xff\xff\xff\xf6")
  assert_eq(ser(0), b"\x00\x00\x00\x00")
  assert_eq(ser(-1), b"\xff\xff\xff\xff")
  assert_eq(ser(16909060), b"\x01\x02\x03\x04")
}

///|
test "other fixed width primitives" {
  assert_eq(ser((7).to_byte()), b"\x07")
  assert_eq(ser((-1).to_byte()), b"\xff")
  assert_eq(ser(true), b"\x01")
  assert_eq(ser(false), b"\x00")
  assert_eq(ser((65535).to_uint16()), b"\xff\xff")
  assert_eq(ser((0xAABB).to_uint16()), b"\xaa\xbb")
  assert_eq(ser(1L), b"\x00\x00\x00\x00\x00\x00\x00\x01")
  assert_eq(ser(-1L), b"\xff\xff\xff\xff\xff\xff\xff\xff")
  assert_eq(ser(0x0102030405060708UL), b"\x01\x02\x03\x04\x05\x06\x07\x08")
}

///|
test "floats are IEEE-754 bits big endian" {
  assert_eq(ser(1.5), b"\x3f\xf8\x00\x00\x00\x00\x00\x00")
  assert_eq(ser(-2.0), b"\xc0\x00\x00\x00\x00\x00\x00\x00")
  let f : Float = 2.0
  assert_eq(ser(f), b"\x40\x00\x00\x00")
}

///|
test "option tag encoding" {
  let some7 : Int32? = Some(7)
  assert_eq(ser(some7), b"\x01\x00\x00\x00\x07")
  let none : Int32? = None
  assert_eq(ser(none), b"\x00")
}

///|
test "result is either-like tagged" {
  let ok : Result[Int32, String] = Ok(5)
  assert_eq(ser(ok), b"\x01\x00\x00\x00\x05")
  let err : Result[Int32, String] = Err("no")
  assert_eq(ser(err), b"\x00\x04\x6e\x6f")
}

///|
test "counted collection encoding" {
  // zigzag(3) = 6, then three big-endian i32 payloads
  assert_eq(
    ser([1, 2, 3]),
    b"\x06\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00\x03",
  )
  assert_eq(ser(([] : Array[Int32])), b"\x00")
}

///|
test "byte block uses unsigned varint prefix" {
  // Matches the Scala Chunk[Byte] / Rust Vec<u8> special case:
  // var_u32(4) + raw bytes.
  assert_eq(ser(b"\x01\x02\x03\x04"), b"\x04\x01\x02\x03\x04")
}

///|
test "strings are utf-8 with zigzag varint length" {
  assert_eq(ser("hello"), b"\x0a\x68\x65\x6c\x6c\x6f")
  assert_eq(ser(""), b"\x00")
  // U+03BB = UTF-8 0xCE 0xBB
  assert_eq(ser("λ"), b"\x04\xce\xbb")
  // U+1F600 = UTF-8 0xF0 0x9F 0x98 0x80
  assert_eq(ser("😀"), b"\x08\xf0\x9f\x98\x80")
}

///|
test "char default encoding is varint scalar value" {
  assert_eq(ser('A'), b"\x41")
  // U+03BB = 955 = LEB128 0xBB 0x07
  assert_eq(ser('λ'), b"\xbb\x07")
}

///|
test "char scala compatible encoding is utf16 unit" {
  let res : Result[Bytes, @desert.DesertFailure] = Ok(
    @desert.serialize_to_bytes('A', options=@desert.Options::scala_compatible()),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(b) => assert_eq(b, b"\x00\x41")
    Err(f) => abort("\{f}")
  }
}

///|
test "dedup strings first occurrence inline, repeats by negative id" {
  // Verified byte dump (desert-rust 0.1.11):
  // Dedup("same"), Dedup("same"), Dedup(""), Dedup("")
  // 08 73 61 6d 65  |  01 (=-1 -> id 1)  |  00 (empty string)  |  03 (=-2 -> id 2)
  let data = ser([
    @desert.DeduplicatedString::new("same"),
    @desert.DeduplicatedString::new("same"),
    @desert.DeduplicatedString::new(""),
    @desert.DeduplicatedString::new(""),
  ])
  assert_eq(data, b"\x08\x08\x73\x61\x6d\x65\x01\x00\x03")
  let round : Array[@desert.DeduplicatedString] = deser(data)
  assert_eq(round[0].get(), "same")
  assert_eq(round[1].get(), "same")
  assert_eq(round[2].get(), "")
  assert_eq(round[3].get(), "")
}

///|
test "tuple is version-0 record" {
  assert_eq(ser((42, true)), b"\x00\x00\x00\x00\x2a\x01")
  // Wire-identical to a plain struct of the same shape:
  assert_eq(ser((42, "x")), b"\x00\x00\x00\x00\x2a\x02\x78")
}

///|
test "hashmap entries are 2-tuples" {
  // Verified byte dump (desert-rust 0.1.11):
  // var_i32(1)=02, entry: 00 (tuple marker), key "a"=02 61, value 1=00000001
  let map : Map[String, Int32] = { "a": 1 }
  let res : Result[Bytes, @desert.DesertFailure] = Ok(
    @desert.serialize_to_bytes(map),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(b) => {
      assert_eq(b.length(), 8)
      assert_eq(b[0].to_int(), 2)
      // zigzag(1) = 2
      assert_eq(b[1], b'\x00')
      // tuple marker
      assert_eq(b[2], b'\x02')
      assert_eq(b[3], b'a')
      assert_eq(b[4], b'\x00')
      assert_eq(b[5], b'\x00')
      assert_eq(b[6], b'\x00')
      assert_eq(b[7], b'\x01')
    }
    Err(f) => abort("\{f}")
  }
  ignore(map)
}

///|
test "string dedup session isolation across calls" {
  // Two separate top-level calls must not share dedup ids.
  let a = ser([
    @desert.DeduplicatedString::new("dup"),
    @desert.DeduplicatedString::new("dup"),
  ])
  let b = ser([
    @desert.DeduplicatedString::new("dup"),
    @desert.DeduplicatedString::new("dup"),
  ])
  assert_eq(a, b)
  assert_eq(a, b"\x04\x06\x64\x75\x70\x01")
}

///|
test "roundtrips of primitives" {
  assert_eq(rt(123456789), 123456789)
  assert_eq(rt(-123456789), -123456789)
  assert_eq(rt((-128).to_byte()), (-128).to_byte())
  assert_eq(rt((65533).to_uint16()), (65533).to_uint16())
}

///|
/// Whitebox-style coverage of the unknown-size iterable form through the
/// public API: an iterator with no known length is written with the
/// `-1` + tagged-element encoding, and the array reader accepts it.

///|
test "unknown size iter form roundtrips into array" {
  let ctx_out = @desert.ByteOutput::new()
  let ctx = @desert.SerializationContext::new(
    ctx_out,
    @desert.SerializerState::new(),
    @desert.Options::default(),
  )
  ctx.write_iter_unknown_size([7, 8].iter())
  let data = ctx_out.to_bytes()
  // zz(-1) = 1, then 01 + payload per element, then 00
  assert_eq(data, b"\x01\x01\x00\x00\x00\x07\x01\x00\x00\x00\x08\x00")
  let res : Result[Array[Int32], @desert.DesertFailure] = Ok(
    @desert.deserialize_exhaustive(data),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(arr) => {
      assert_eq(arr.length(), 2)
      assert_eq(arr[0], 7)
      assert_eq(arr[1], 8)
    }
    Err(f) => abort("\{f}")
  }
}

///|
test "serialized_size matches serialized length" {
  let size_hello : Int32 = @desert.serialized_size("hello") catch { _ => -1 }
  assert_eq(size_hello, 6)
  let size_arr : Int32 = @desert.serialized_size([1, 2, 3]) catch { _ => -1 }
  assert_eq(size_arr, 13)
}

///|
test "chars_as_u16 mode rejects astral characters" {
  let res : Result[Bytes, @desert.DesertFailure] = Ok(
    @desert.serialize_to_bytes(
      '😀',
      options=@desert.Options::scala_compatible(),
    ),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(@desert.UnsupportedCharacter(ch)) => assert_eq(ch, '😀')
    _ => abort("expected UnsupportedCharacter")
  }
}

///|
test "nested option and array structures" {
  let value : Array[Int32?] = [Some(1), None, Some(3)]
  let data = ser(value)
  assert_eq(data, b"\x06\x01\x00\x00\x00\x01\x00\x01\x00\x00\x00\x03")
  let back : Array[Int32?] = deser(data)
  assert_eq(back.length(), 3)
  assert_eq(back[1], None)
  assert_eq(back[2], Some(3))
}

///|
test "char scala compatible roundtrip of BMP character" {
  let data = ser_with_options('λ', @desert.Options::scala_compatible())
  assert_eq(data, b"\x03\xbb")
  let res : Result[Char, @desert.DesertFailure] = Ok(
    @desert.deserialize_exhaustive(
      data,
      options=@desert.Options::scala_compatible(),
    ),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(ch) => assert_eq(ch, 'λ')
    Err(f) => abort("\{f}")
  }
}

///|
fn[T : @desert.BinarySerializer] ser_with_options(
  value : T,
  options : @desert.Options,
) -> Bytes {
  let res : Result[Bytes, @desert.DesertFailure] = Ok(
    @desert.serialize_to_bytes(value, options~),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(b) => b
    Err(f) => abort("\{f}")
  }
}
