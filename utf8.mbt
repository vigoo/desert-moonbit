///|
/// Number of UTF-8 bytes needed to encode `s`.
///
/// MoonBit strings are UTF-16 internally; lone surrogates are counted as one
/// byte because they are encoded as the ASCII `?` substitution character
/// (matching Scala's `String.getBytes(UTF_8)` REPLACE behavior).
pub fn utf8_byte_length(s : String) -> Int32 {
  let mut total = 0
  let len = s.length()
  let mut i = 0
  while i < len {
    let unit = s[i].to_int()
    if unit < 0x80 {
      total = total + 1
      i = i + 1
    } else if unit < 0x800 {
      total = total + 2
      i = i + 1
    } else if unit < 0xD800 || unit > 0xDFFF {
      total = total + 3
      i = i + 1
    } else if unit <= 0xDBFF &&
      i + 1 < len &&
      s[i + 1].to_int() >= 0xDC00 &&
      s[i + 1].to_int() <= 0xDFFF {
      // Surrogate pair, encodes as 4 bytes.
      total = total + 4
      i = i + 2
    } else {
      // Lone surrogate, substituted with '?'.
      total = total + 1
      i = i + 1
    }
  }
  total
}

///|
/// Encode `s` as UTF-8 into `out`, which must have space for at least
/// `utf8_byte_length(s)` bytes. Returns the number of bytes written.
///
/// Lone surrogates are substituted with the ASCII `?` character (0x3F),
/// matching Scala's `String.getBytes(UTF_8)` replacement behavior.
pub fn write_utf8(s : String, out : FixedArray[Byte], offset : Int32) -> Int32 {
  let mut i = offset
  let len = s.length()
  let mut j = 0
  while j < len {
    let unit = s[j].to_int()
    if unit < 0x80 {
      out[i] = unit.to_byte()
      i = i + 1
      j = j + 1
    } else if unit < 0x800 {
      out[i] = (0xC0 | (unit >> 6)).to_byte()
      out[i + 1] = (0x80 | (unit & 0x3F)).to_byte()
      i = i + 2
      j = j + 1
    } else if unit < 0xD800 || unit > 0xDFFF {
      out[i] = (0xE0 | (unit >> 12)).to_byte()
      out[i + 1] = (0x80 | ((unit >> 6) & 0x3F)).to_byte()
      out[i + 2] = (0x80 | (unit & 0x3F)).to_byte()
      i = i + 3
      j = j + 1
    } else if unit <= 0xDBFF &&
      j + 1 < len &&
      s[j + 1].to_int() >= 0xDC00 &&
      s[j + 1].to_int() <= 0xDFFF {
      let hi = unit - 0xD800
      let lo = s[j + 1].to_int() - 0xDC00
      let cp = 0x10000 + (hi << 10) + lo
      out[i] = (0xF0 | (cp >> 18)).to_byte()
      out[i + 1] = (0x80 | ((cp >> 12) & 0x3F)).to_byte()
      out[i + 2] = (0x80 | ((cp >> 6) & 0x3F)).to_byte()
      out[i + 3] = (0x80 | (cp & 0x3F)).to_byte()
      i = i + 4
      j = j + 2
    } else {
      out[i] = b'?'
      i = i + 1
      j = j + 1
    }
  }
  i - offset
}

///|
/// Decode UTF-8 bytes into a MoonBit (UTF-16) string.
///
/// Malformed sequences fail with `DeserializationFailure`, matching the Rust
/// library (`String::from_utf8`). All standard UTF-8 forms are accepted,
/// including 4-byte sequences for astral code points.
pub fn read_utf8(bytes : BytesView) -> String raise DesertFailure {
  let len = bytes.length()
  let sb = StringBuilder()
  let mut i = 0
  while i < len {
    let b0 = bytes[i].to_int()
    if b0 < 0x80 {
      sb.write_char(b0.unsafe_to_char())
      i = i + 1
    } else if b0 < 0xC0 {
      // Continuation byte as a leading byte.
      raise DeserializationFailure(
        "Failed to decode string: invalid UTF-8 leading byte",
      )
    } else if b0 < 0xE0 {
      i = decode_2_bytes(bytes, i, b0, sb)
    } else if b0 < 0xF0 {
      i = decode_3_bytes(bytes, i, b0, sb)
    } else if b0 < 0xF8 {
      i = decode_4_bytes(bytes, i, b0, sb)
    } else {
      raise DeserializationFailure(
        "Failed to decode string: invalid UTF-8 leading byte",
      )
    }
  }
  sb.to_string()
}

///|
fn continuation(bytes : BytesView, i : Int32) -> Int32 raise DesertFailure {
  if i >= bytes.length() {
    raise DeserializationFailure(
      "Failed to decode string: truncated UTF-8 sequence",
    )
  }
  let b = bytes[i].to_int()
  if (b & 0xC0) != 0x80 {
    raise DeserializationFailure(
      "Failed to decode string: invalid UTF-8 continuation byte",
    )
  }
  b & 0x3F
}

///|
fn decode_2_bytes(
  bytes : BytesView,
  i : Int32,
  b0 : Int32,
  sb : StringBuilder,
) -> Int32 raise DesertFailure {
  let cp = ((b0 & 0x1F) << 6) | continuation(bytes, i + 1)
  if cp < 0x80 {
    raise DeserializationFailure(
      "Failed to decode string: overlong UTF-8 sequence",
    )
  }
  sb.write_char(cp.unsafe_to_char())
  i + 2
}

///|
fn decode_3_bytes(
  bytes : BytesView,
  i : Int32,
  b0 : Int32,
  sb : StringBuilder,
) -> Int32 raise DesertFailure {
  let cp = ((b0 & 0x0F) << 12) |
    (continuation(bytes, i + 1) << 6) |
    continuation(bytes, i + 2)
  if cp < 0x800 {
    raise DeserializationFailure(
      "Failed to decode string: overlong UTF-8 sequence",
    )
  }
  if cp >= 0xD800 && cp <= 0xDFFF {
    raise DeserializationFailure(
      "Failed to decode string: UTF-8 encoded surrogate",
    )
  }
  sb.write_char(cp.unsafe_to_char())
  i + 3
}

///|
fn decode_4_bytes(
  bytes : BytesView,
  i : Int32,
  b0 : Int32,
  sb : StringBuilder,
) -> Int32 raise DesertFailure {
  let cp = ((b0 & 0x07) << 18) |
    (continuation(bytes, i + 1) << 12) |
    (continuation(bytes, i + 2) << 6) |
    continuation(bytes, i + 3)
  if cp < 0x10000 || cp > 0x10FFFF {
    raise DeserializationFailure(
      "Failed to decode string: invalid UTF-8 code point",
    )
  }
  sb.write_char(cp.unsafe_to_char())
  i + 4
}
