///|
/// Compressed byte blocks, matching desert-rust's `write_compressed`/
/// `read_compressed`: `var_u32(uncompressed_length)`,
/// `var_u32(compressed_length)`, then raw DEFLATE data.
///
/// Note that the original Scala implementation writes only the uncompressed
/// length for empty arrays; desert-rust (followed here) always writes both
/// lengths. Decompression failures surface as `DeserializationFailure`.

///|
/// Write `data` DEFLATE-compressed into the output.
pub fn SerializationContext::write_compressed(
  self : SerializationContext,
  data : Bytes,
) -> Unit raise DesertFailure {
  let len = data.length()
  self.write_var_u32(len.reinterpret_as_uint())
  let compressed = @flate.deflate_all(data.exact_view())
  self.write_var_u32(compressed.length().reinterpret_as_uint())
  if compressed.length() > 0 {
    self.write_bytes(compressed.exact_view())
  }
}

///|
/// Read a DEFLATE-compressed byte block.
pub fn DeserializationContext::read_compressed(
  self : DeserializationContext,
) -> Bytes raise DesertFailure {
  let uncompressed_len = self.read_var_u32().reinterpret_as_int()
  let compressed_len = self.read_var_u32().reinterpret_as_int()
  if compressed_len < 0 || uncompressed_len < 0 {
    raise DeserializationFailure("Negative compressed block length")
  }
  if compressed_len == 0 {
    if uncompressed_len != 0 {
      raise DeserializationFailure(
        "Empty compressed block with non-zero uncompressed length",
      )
    }
    return Bytes::new(0)
  }
  let compressed = self.input.read_bytes(compressed_len)
  let res : Result[Bytes, @flate.InflateError] = Ok(
    @flate.inflate_exact(compressed.exact_view()),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(data) => data
    Err(_) => raise DeserializationFailure("Failed to decompress data block")
  }
}

///|
/// Round-trip helpers for testing and ad-hoc use.
pub fn compress_bytes(data : Bytes) -> Bytes raise DesertFailure {
  let out = ByteOutput::new()
  let ctx = SerializationContext::new(
    out,
    SerializerState::new(),
    Options::default(),
  )
  ctx.write_compressed(data)
  out.to_bytes()
}

///|
pub fn decompress_bytes(data : Bytes) -> Bytes raise DesertFailure {
  let ctx = DeserializationContext::new(
    BinaryInput::new(data),
    SerializerState::new(),
    Options::default(),
  )
  ctx.read_compressed()
}
