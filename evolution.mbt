///|
/// Schema evolution steps, mirroring the Scala `Evolution` sealed trait and
/// the Rust `Evolution` enum.
///
/// A record's evolution history is declared as `InitialVersion` followed by
/// one step per schema change; the list length determines the wire version
/// byte (`steps.length() - 1`).
pub(all) enum Evolution {
  InitialVersion
  /// Add a new field to a record. The default value is supplied by the
  /// reading codec, not stored on the wire.
  FieldAdded(String)
  /// An existing non-option field is made optional.
  FieldMadeOptional(String)
  /// Field removed from the record.
  FieldRemoved(String)
  /// Field made transient — an alias for `FieldRemoved` on the wire.
  FieldMadeTransient(String)
}

///|
/// Wire codes of serialized evolution steps.
const EVOLUTION_STEP_UNKNOWN : Int32 = 0

///|
const EVOLUTION_STEP_FIELD_MADE_OPTIONAL : Int32 = -1

///|
const EVOLUTION_STEP_FIELD_REMOVED : Int32 = -2

///|
/// Position of a field inside the evolved record layout, as referenced by
/// `FieldMadeOptional` header entries.
///
/// Wire encoding is a single byte: for chunk 0 the negated position
/// (so the reader can distinguish it from a chunk index), otherwise the
/// chunk number (position 0 implied).
priv struct FieldPosition {
  chunk : Int32
  position : Int32
}

///|
fn FieldPosition::new(chunk : Int32, position : Int32) -> FieldPosition {
  { chunk, position, }
}

///|
fn FieldPosition::to_byte(self : FieldPosition) -> Int32 {
  if self.chunk == 0 {
    -self.position
  } else {
    self.chunk
  }
}

///|
fn FieldPosition::from_byte(byte : Int32) -> FieldPosition {
  if byte < 0 {
    FieldPosition::new(0, -byte)
  } else {
    FieldPosition::new(byte, 0)
  }
}

///|
/// Static description of a record's evolution history, shared by the writer
/// and the reader. Build once per record type (e.g. as a toplevel `let`) via
/// `AdtMetadata::new`.
pub struct AdtMetadata {
  /// Wire version: `evolution_steps.length() - 1`.
  version : Int32
  /// Field name -> index of the `FieldAdded` step that introduced it
  /// (0 if present from the start).
  field_generations : @hashmap.HashMap[String, Int32]
  /// Field name -> index of its `FieldMadeOptional` step.
  made_optional_at : @hashmap.HashMap[String, Int32]
  /// Names removed by `FieldRemoved`/`FieldMadeTransient` steps.
  removed_fields : @hashmap.HashMap[String, Bool]
  /// The declared steps, including the leading `InitialVersion`.
  evolution_steps : Array[Evolution]
  /// True when any step is `FieldMadeOptional` (enables field-position
  /// tracking, which is only needed to disambiguate those entries).
  contains_field_made_optional : Bool
}

///|
/// Build the metadata for a record declared with `steps`
/// (`InitialVersion` first, then one entry per schema change).
///
/// Panics with more than 255 steps (the version byte is a single `u8`).
pub fn AdtMetadata::new(steps : Array[Evolution]) -> AdtMetadata {
  if steps.length() > 255 {
    abort("desert: too many evolution steps (max 255)")
  }
  let field_generations : @hashmap.HashMap[String, Int32] = @hashmap.HashMap([])
  let made_optional_at : @hashmap.HashMap[String, Int32] = @hashmap.HashMap([])
  let removed_fields : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  for i, step in steps {
    match step {
      FieldAdded(name) => field_generations.set(name, i)
      FieldMadeOptional(name) => made_optional_at.set(name, i)
      FieldRemoved(name) | FieldMadeTransient(name) =>
        removed_fields.set(name, true)
      InitialVersion => ()
    }
  }
  {
    version: steps.length() - 1,
    field_generations,
    made_optional_at,
    removed_fields,
    evolution_steps: steps,
    contains_field_made_optional: !made_optional_at.is_empty(),
  }
}

///|
fn AdtMetadata::generation_of(self : AdtMetadata, field_name : String) -> Int32 {
  match self.field_generations.get(field_name) {
    Some(generation) => generation
    None => 0
  }
}

///|
/// A serialized evolution header entry (wire form).
priv enum SerializedEvolutionStep {
  /// Positive (or zero) size: a data chunk with this many bytes follows.
  FieldAddedToNewChunk(Int32)
  /// -1 + position byte.
  FieldMadeOptionalStep(FieldPosition)
  /// -2 + deduplicated field name.
  FieldRemovedStep(String)
  /// 0 — written by unknown future steps; ignored by older readers.
  UnknownStep
}

///|
fn SerializedEvolutionStep::serialize(
  self : SerializedEvolutionStep,
  ctx : SerializationContext,
) -> Unit raise DesertFailure {
  match self {
    FieldAddedToNewChunk(size) => ctx.write_var_i32(size)
    FieldMadeOptionalStep(position) => {
      ctx.write_var_i32(EVOLUTION_STEP_FIELD_MADE_OPTIONAL)
      ctx.write_u8(position.to_byte().to_byte())
    }
    FieldRemovedStep(field_name) => {
      ctx.write_var_i32(EVOLUTION_STEP_FIELD_REMOVED)
      DeduplicatedString::new(field_name).serialize(ctx)
    }
    UnknownStep => ctx.write_var_i32(EVOLUTION_STEP_UNKNOWN)
  }
}

///|
fn SerializedEvolutionStep::deserialize(
  ctx : DeserializationContext,
) -> SerializedEvolutionStep raise DesertFailure {
  let code_or_size = ctx.read_var_i32()
  if code_or_size == EVOLUTION_STEP_UNKNOWN {
    return UnknownStep
  }
  if code_or_size == EVOLUTION_STEP_FIELD_MADE_OPTIONAL {
    return FieldMadeOptionalStep(FieldPosition::from_byte(ctx.read_i8()))
  }
  if code_or_size == EVOLUTION_STEP_FIELD_REMOVED {
    return FieldRemovedStep(DeduplicatedString::deserialize(ctx).get())
  }
  if code_or_size < 0 {
    // Negative codes other than -1/-2 are unknown encodings.
    raise UnknownSerializedEvolutionStep(code_or_size)
  }
  FieldAddedToNewChunk(code_or_size)
}
