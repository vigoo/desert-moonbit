///|
/// String codec: `var_i32(UTF-8 byte length)` followed by the UTF-8 bytes.
pub impl BinarySerializer for String with fn serialize(self, ctx) {
  ctx.write_string_payload(self)
}

///|
pub impl BinaryDeserializer for String with fn deserialize(ctx) {
  ctx.read_string_payload()
}

///|
/// `Char` codec.
///
/// Default mode encodes the Unicode scalar value as a raw (non-zigzag)
/// varint, matching desert-rust. With `chars_as_u16` set on the context the
/// encoding is one big-endian 16-bit UTF-16 unit, byte-compatible with the
/// Scala library; astral characters fail with `UnsupportedCharacter` in that
/// mode (they are 4 bytes in the default mode).
pub impl BinarySerializer for Char with fn serialize(self, ctx) {
  if ctx.options.chars_as_u16 {
    let cp = self.to_int()
    if cp > 0xFFFF {
      raise UnsupportedCharacter(self)
    }
    ctx.write_u16((cp & 0xFFFF).to_uint16())
  } else {
    ctx.write_var_u32(self.to_int().reinterpret_as_uint())
  }
}

///|
pub impl BinaryDeserializer for Char with fn deserialize(ctx) {
  if ctx.options.chars_as_u16 {
    let unit = ctx.input.read_u16()
    match unit.to_char() {
      Some(ch) => ch
      None => raise FailedToDecodeCharacter(unit)
    }
  } else {
    let cp = ctx.input.read_var_u32().reinterpret_as_int()
    // Validate like desert-rust: reject out-of-range and surrogate values
    // instead of materializing an invalid Char.
    if cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
      raise DeserializationFailure(
        "Failed to decode character: invalid code point \{cp}",
      )
    }
    cp.unsafe_to_char()
  }
}

///|
/// Opt-in string deduplication wrapper (mirrors `DeduplicatedString` in both
/// existing implementations).
///
/// The first occurrence is written as a normal string and registered in the
/// session's dedup table; every later occurrence is written as the
/// zigzag-encoded negative id (`var_i32(-id)`). Ids start from 1. On the
/// reading side every inline string is registered, so a negative value not
/// present in the table fails with `InvalidStringId`.
///
/// Do not mix deduplicated and plain string fields inside evolvable records:
/// an older reader skipping a newly added deduplicated field would miss an id
/// assignment and every later back-reference would be corrupted. Plain
/// `String` fields are always evolution-safe.
#derive(Debug, Eq)
pub struct DeduplicatedString {
  priv string : String
}

///|
pub fn DeduplicatedString::new(string : String) -> DeduplicatedString {
  DeduplicatedString::{ string, }
}

///|
/// The wrapped string.
pub fn DeduplicatedString::get(self : DeduplicatedString) -> String {
  self.string
}

///|
pub impl BinarySerializer for DeduplicatedString with fn serialize(self, ctx) {
  match ctx.state.store_string(self.string) {
    StringAlreadyStored(id) => ctx.write_var_i32(-id)
    StringIsNew(_id) => ctx.write_string_payload(self.string)
  }
}

///|
pub impl BinaryDeserializer for DeduplicatedString with fn deserialize(ctx) {
  let count_or_id = ctx.read_var_i32()
  if count_or_id < 0 {
    let id = -count_or_id
    match ctx.state.get_string(id) {
      Some(s) => DeduplicatedString::{ string: s, }
      None => raise InvalidStringId(id)
    }
  } else {
    // count_or_id is the UTF-8 byte length of an inline string (registered
    // under the next id).
    let s = read_utf8(ctx.input.read_bytes_view(count_or_id))
    ctx.state.store_read_string(s)
    DeduplicatedString::{ string: s, }
  }
}

///|
pub extend DeduplicatedString with BinaryDeserializer::{deserialize}

///|
pub extend DeduplicatedString with BinarySerializer::{serialize}

///|
pub extend DeduplicatedString with Eq::{not_equal, equal}

///|
pub extend DeduplicatedString with @moonbitlang/core/debug.Debug::{to_repr}
