///|
/// Compressed byte block round-trips: format is
/// `var_u32(uncompressed) var_u32(compressed) deflate(bytes)`.

///|
test "compressed block roundtrip" {
  let original = Bytes::repeat(b"desert compressed block data ", 1000)
  let compressed = compress_bytes(original)
  // Compression must actually shrink this repetitive payload.
  assert_eq(compressed.length() < original.length(), true)
  let back = decompress_bytes(compressed)
  assert_eq(back, original)
}

///|
test "compressed empty block" {
  let empty = Bytes::new(0)
  let compressed = compress_bytes(empty)
  // var_u32(0) + var_u32(len(deflate([]))) + deflate bytes
  assert_eq(compressed[0], b'\x00')
  let back = decompress_bytes(compressed)
  assert_eq(back.length(), 0)
}

///|
test "compressed block wire layout" {
  // Exact wire check with a tiny payload: uncompressed varint, compressed
  // varint, then the deflate stream (its exact bytes are implementation
  // defined, so only the layout is asserted).
  let payload = b"\x01\x02\x03"
  let compressed = compress_bytes(payload)
  assert_eq(compressed[0], b'\x03')
  // The rest is the compressed length varint + deflate stream.
  assert_eq(compressed.length() > 3, true)
  let back = decompress_bytes(compressed)
  assert_eq(back, payload)
}

///|
test "corrupt compressed block fails cleanly" {
  let payload = b"some data to compress"
  let compressed = compress_bytes(payload)
  // Corrupt the deflate stream bytes.
  let corrupted : FixedArray[Byte] = FixedArray::make(
    compressed.length(),
    b'\x00',
  )
  FixedArray::blit_from_bytes(corrupted, 0, compressed, 0, compressed.length())
  corrupted[compressed.length() - 1] = b'\xff'
  corrupted[compressed.length() - 2] = b'\xff'
  let corrupted_bytes = Bytes::from_array(corrupted)
  let res : Result[Bytes, DesertFailure] = Ok(decompress_bytes(corrupted_bytes)) catch {
    e => Err(e)
  }
  match res {
    Err(DeserializationFailure("Failed to decompress data block")) => ()
    Err(other) => abort("expected decompression failure, got \{other}")
    Ok(_) => abort("expected a failure")
  }
}

///|
/// Compressed blocks interoperate with the generic codecs: a Bytes payload
/// written compressed and read back inside an Option.
test "compressed block inside option roundtrip" {
  let payload = Bytes::repeat(b"x", 500)
  let ctx_out = ByteOutput::new()
  let ctx = SerializationContext::new(
    ctx_out,
    SerializerState::new(),
    Options::default(),
  )
  let wrapped : Bytes? = Some(payload)
  ctx.write(wrapped)
  let bytes = ctx_out.to_bytes()
  let in_ctx = DeserializationContext::new(
    BinaryInput::new(bytes),
    SerializerState::new(),
    Options::default(),
  )
  let back : Bytes? = BinaryDeserializer::deserialize(in_ctx)
  match back {
    Some(b) => assert_eq(b, payload)
    None => abort("expected Some")
  }
}
