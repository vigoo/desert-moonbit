///|
/// Per-call serialization options.
///
/// These flags only change the wire format when set; both sides of a stream
/// must agree on them (same contract as desert-rust's `Options`).
#derive(Debug, Default)
pub struct Options {
  /// Encode `Char` as one big-endian 16-bit UTF-16 unit, matching the Scala
  /// library. The default encodes the Unicode scalar value as a raw varint.
  /// Astral characters cannot be encoded in this mode and fail with
  /// `UnsupportedCharacter`.
  chars_as_u16 : Bool
}

///|
/// Options matching the original Scala library's wire behavior.
pub fn Options::scala_compatible() -> Options {
  { chars_as_u16: true, }
}

///|
pub extend Options with Default::{default}

///|
pub extend Options with @moonbitlang/core/debug.Debug::{to_repr}
