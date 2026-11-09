///|
/// Per-call context for serialization: the output sink, the session state
/// (string dedup / reference tracking) and the format options.
///
/// The active output can be swapped by the evolution machinery
/// (`push_output`/`pop_output`) so that a record's fields are captured into
/// per-generation chunk buffers.
pub struct SerializationContext {
  priv mut output : &BinaryOutput
  priv mut output_stack : Array[&BinaryOutput]
  state : SerializerState
  options : Options
}

///|
/// Per-call context for deserialization: the input cursor, the session state
/// and the format options. The state table is filled as strings are read.
pub struct DeserializationContext {
  input : BinaryInput
  state : SerializerState
  options : Options
}

///|
/// Serialization is implemented as a single method taking the context;
/// failures are raised as `DesertFailure`.
pub(open) trait BinarySerializer {
  fn serialize(Self, ctx : SerializationContext) -> Unit raise DesertFailure
}

///|
/// Deserialization mirrors `BinarySerializer`: the method returns the
/// decoded value of its own type.
pub(open) trait BinaryDeserializer {
  fn deserialize(ctx : DeserializationContext) -> Self raise DesertFailure
}

///|
/// A type that can be both serialized and deserialized. Implement this
/// (together with the two component traits) for your own types, or let
/// `desert-codegen` generate the implementations.
pub(open) trait BinaryCodec {}

///|
/// Write a value of any `BinarySerializer` type into the context.
pub fn[T : BinarySerializer] SerializationContext::write(
  self : SerializationContext,
  value : T,
) -> Unit raise DesertFailure {
  value.serialize(self)
}

///|
/// Read a value of any `BinaryDeserializer` type from the context.
pub fn[T : BinaryDeserializer] DeserializationContext::read(
  self : DeserializationContext,
) -> T raise DesertFailure {
  T::deserialize(self)
}

///|
/// Construct a serialization context over a custom output sink.
pub fn SerializationContext::new(
  output : &BinaryOutput,
  state : SerializerState,
  options : Options,
) -> SerializationContext {
  { output, output_stack: [], state, options, }
}

///|
/// Construct a deserialization context over a custom input.
pub fn DeserializationContext::new(
  input : BinaryInput,
  state : SerializerState,
  options : Options,
) -> DeserializationContext {
  { input, state, options, }
}
