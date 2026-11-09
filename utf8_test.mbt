///|
/// UTF-8 transcoder edge cases (wire-compatible behavior with the original
/// libraries: encode substitutes lone surrogates like Scala's
/// `getBytes(UTF_8)`, decode rejects malformed input like Rust's
/// `String::from_utf8`).

///|
test "utf8 byte length counts pairs as 4 and lone surrogates as 1" {
  assert_eq(@desert.utf8_byte_length(""), 0)
  assert_eq(@desert.utf8_byte_length("hello"), 5)
  assert_eq(@desert.utf8_byte_length("λ"), 2)
  assert_eq(@desert.utf8_byte_length("😀"), 4)
  // A string built from a lone surrogate unit: substituted, so 1 byte.
  let lone = StringBuilder()
  lone.write_char((0xD83D).unsafe_to_char())
  assert_eq(@desert.utf8_byte_length(lone.to_string()), 1)
}

///|
test "utf8 encode substitutes lone surrogates with question mark" {
  let lone = StringBuilder()
  lone.write_char((0xD83D).unsafe_to_char())
  let s = lone.to_string()
  let out : FixedArray[Byte] = FixedArray::make(1, b'\x00')
  let written = @desert.write_utf8(s, out, 0)
  assert_eq(written, 1)
  assert_eq(out[0], b'?')
}

///|
fn decode(bytes : FixedArray[Byte]) -> String {
  let res : Result[String, @desert.DesertFailure] = Ok(
    @desert.read_utf8(Bytes::from_array(bytes).exact_view()),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(s) => s
    Err(f) => abort("\{f}")
  }
}

///|
fn decode_fails(bytes : FixedArray[Byte]) -> Bool {
  let res : Result[String, @desert.DesertFailure] = Ok(
    @desert.read_utf8(Bytes::from_array(bytes).exact_view()),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(_) => false
    Err(_) => true
  }
}

///|
test "utf8 decode accepts standard sequences" {
  assert_eq(decode([b'\xce', b'\xbb']), "λ")
  assert_eq(decode([b'\xf0', b'\x9f', b'\x98', b'\x80']), "😀")
  assert_eq(decode([]), "")
  assert_eq(decode([b'h', b'i']), "hi")
}

///|
test "utf8 decode rejects malformed input" {
  // Overlong encoding of 'A' (0xC1 0x81).
  assert_eq(decode_fails([b'\xc1', b'\x81']), true)
  // UTF-8 encoded surrogate (0xED 0xA0 0xBD).
  assert_eq(decode_fails([b'\xed', b'\xa0', b'\xbd']), true)
  // Truncated 2-byte sequence.
  assert_eq(decode_fails([b'\xce']), true)
  // Continuation byte as leading byte.
  assert_eq(decode_fails([b'\x80']), true)
}
