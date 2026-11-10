///|
/// Serialize `value` to an in-memory byte buffer, returning the bytes.
///
/// A fresh session state (string dedup table, reference table) is created
/// for the call, matching the top-level APIs of both existing
/// implementations: ids never leak across calls.
pub fn[T : BinarySerializer] serialize_to_bytes(
  value : T,
  options~ : Options = Options::default(),
) -> Bytes raise DesertFailure {
  let out = ByteOutput::new()
  let ctx : SerializationContext = {
    output: out,
    output_stack: [],
    state: SerializerState::new(),
    options,
  }
  value.serialize(ctx)
  out.to_bytes()
}

///|
/// Serialize `value` into a caller-provided `ByteOutput`.
pub fn[T : BinarySerializer] serialize_to_output(
  value : T,
  out : ByteOutput,
  options~ : Options = Options::default(),
) -> Unit raise DesertFailure {
  let ctx : SerializationContext = {
    output: out,
    output_stack: [],
    state: SerializerState::new(),
    options,
  }
  value.serialize(ctx)
}

///|
/// Compute the serialized size of `value` in bytes (the bytes are written
/// to a scratch output and discarded). Two-pass exact-size serialization
/// can be built on this.
pub fn[T : BinarySerializer] serialized_size(
  value : T,
  options~ : Options = Options::default(),
) -> Int32 raise DesertFailure {
  let out = ByteOutput::new()
  let ctx : SerializationContext = {
    output: out,
    output_stack: [],
    state: SerializerState::new(),
    options,
  }
  value.serialize(ctx)
  out.length()
}

///|
/// Deserialize a value of type `T` from `data`.
///
/// The input must have been produced by a compatible serializer (same
/// options, same schema version). Underruns and format violations raise
/// `DesertFailure`.
pub fn[T : BinaryDeserializer] deserialize(
  data : Bytes,
  options~ : Options = Options::default(),
) -> T raise DesertFailure {
  let ctx : DeserializationContext = {
    input: BinaryInput::new(data),
    state: SerializerState::new(),
    options,
  }
  T::deserialize(ctx)
}

///|
/// Deserialize a value of type `T` from `data`, additionally checking that
/// the whole input was consumed. Trailing bytes fail with
/// `DeserializationFailure`, which catches framing mistakes early.
pub fn[T : BinaryDeserializer] deserialize_exhaustive(
  data : Bytes,
  options~ : Options = Options::default(),
) -> T raise DesertFailure {
  let ctx : DeserializationContext = {
    input: BinaryInput::new(data),
    state: SerializerState::new(),
    options,
  }
  let value = T::deserialize(ctx)
  if !ctx.input.is_empty() {
    raise DeserializationFailure("Trailing bytes after deserialized value")
  }
  value
}
