///|
/// The failure taxonomy of desert.
///
/// Byte-for-byte mirror of the `DesertFailure` sealed trait of the original
/// Scala library (and the `Error` enum of desert-rust): every variant that can
/// appear on a wire-relevant code path exists here, so failure *identities*
/// round-trip across implementations.
///
/// Causes are flattened into the message payload; the original library carried
/// an optional `cause` exception which has no MoonBit counterpart.
#derive(Debug)
pub(all) suberror DesertFailure {
  /// I/O error while reading the input.
  FailedToReadInput(String)
  /// The input ended before a complete value could be read.
  InputEndedUnexpectedly
  /// I/O error while writing the output.
  FailedToWriteOutput(String)
  /// Generic serializer failure.
  SerializationFailure(String)
  /// Generic deserializer failure (also used for malformed UTF-8 payloads).
  DeserializationFailure(String)
  /// An evolution chunk index outside the stored range was requested.
  DeserializingNonExistingChunk(Int32)
  /// An old codec read a non-optional field that is now serialized as `None`.
  NonOptionalFieldSerializedAsNone(String)
  /// An evolution step references a field the current model does not have.
  UnknownFieldReferenceInEvolutionStep(String)
  /// The serialized evolution header contains an unknown step code (<= -3).
  UnknownSerializedEvolutionStep(Int32)
  /// A deduplicated-string back-reference points to a never-stored string.
  InvalidStringId(Int32)
  /// A required field was removed in the serialized version.
  FieldRemovedInSerializedVersion(String)
  /// A field is missing in the data and has no `FieldAdded` default.
  FieldWithoutDefaultValueIsMissing(String)
  /// `write_unknown` was called for a runtime type not in the type registry.
  TypeNotRegistered(String)
  /// `read_unknown` encountered a type id that is not in the registry.
  InvalidTypeId(Int32)
  /// A registered value could not be cast/upcast to the requested type.
  SerializationUpcastError(String, String, String)
  /// A coproduct constructor name does not match the codec's declaration.
  InvalidConstructorName(String, String)
  /// A coproduct constructor id is out of range for the codec's declaration.
  InvalidConstructorId(Int32, String)
  /// An object back-reference points to a never-stored object.
  InvalidRefId(Int32)
  /// Attempt to serialize a constructor marked as transient.
  SerializingTransientConstructor(String)
  /// A character cannot be encoded in the selected mode (e.g. an astral
  /// character with `chars_as_u16` set).
  UnsupportedCharacter(Char)
  /// The input contains an invalid UTF-16 code unit where a character was
  /// expected.
  FailedToDecodeCharacter(UInt16)
}

///|
/// Human-readable message, mirroring `DesertFailure.message` of the Scala
/// library (wording kept close to the original where it exists).
pub fn DesertFailure::message(self : DesertFailure) -> String {
  match self {
    FailedToReadInput(reason) => "Failed to read input: \{reason}"
    InputEndedUnexpectedly => "Input ended unexpectedly"
    FailedToWriteOutput(reason) => "Failed to write output: \{reason}"
    SerializationFailure(m) => "Serialization failure: \{m}"
    DeserializationFailure(m) => "Deserialization failure: \{m}"
    DeserializingNonExistingChunk(chunk) =>
      "Trying to deserialize non-existing chunk #\{chunk}"
    NonOptionalFieldSerializedAsNone(field) =>
      "Field \{field} is not optional but it is serialized as none"
    UnknownFieldReferenceInEvolutionStep(field) =>
      "Evolution step refers to unknown field \{field}"
    UnknownSerializedEvolutionStep(code) =>
      "Unknown serialized evolution step with code \{code}"
    InvalidStringId(id) => "Invalid string id #\{id}"
    FieldRemovedInSerializedVersion(field) =>
      "Field \{field} was removed in the serialized version"
    FieldWithoutDefaultValueIsMissing(field) =>
      "Field \{field} is missing and it has no default value"
    TypeNotRegistered(typ) => "Type \{typ} is not registered"
    InvalidTypeId(id) => "Invalid type id #\{id}"
    SerializationUpcastError(value_type, target_type, reason) =>
      "Failed to upcast \{value_type} to \{target_type}: \{reason}"
    InvalidConstructorName(name, typ) =>
      "Invalid constructor name \{name} for type \{typ}"
    InvalidConstructorId(id, typ) =>
      "Invalid constructor id \{id} for type \{typ}"
    InvalidRefId(id) => "Invalid reference id #\{id}"
    SerializingTransientConstructor(name) =>
      "Trying to serialize transient constructor \{name}"
    UnsupportedCharacter(ch) => "Unsupported character: \{ch}"
    FailedToDecodeCharacter(unit) =>
      "Failed to decode character from UTF-16 code unit \{unit}"
  }
}

///|
pub impl Show for DesertFailure with fn to_string(self) {
  self.message()
}

///|
pub extend DesertFailure with Show::{to_string, output}

///|
pub extend DesertFailure with @moonbitlang/core/debug.Debug::{to_repr}
