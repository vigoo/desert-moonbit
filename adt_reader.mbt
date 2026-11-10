///|
/// Reader for evolved records, the runtime engine behind derived codecs
/// (mirrors desert-rust's `AdtDeserializer`).
///
/// The generated (or hand-written) codec first reads the stored version
/// byte, then either uses the direct field reads (both versions are 0) or
/// constructs this reader, which parses the evolution header, fences each
/// chunk behind an input region, and applies the compatibility rules:
///
/// - fields introduced after the stored version fall back to their
///   `FieldAdded` defaults (or fail without one)
/// - fields removed in the serialized version fail on read
///   (`FieldRemovedInSerializedVersion`) — optional fields return `None`
/// - a field made optional after the stored version is read bare and wrapped
///   in `Some`
/// - an old reader finding a made-optional field serialized as `None` fails
///   with `NonOptionalFieldSerializedAsNone`
/// - unknown header entries (code 0) from future versions are ignored
pub struct AdtReader {
  priv metadata : AdtMetadata
  priv ctx : DeserializationContext
  /// The version the data was written with.
  priv stored_version : Int32
  /// FieldPosition -> version index, from the wire header.
  priv made_optional_at : @hashmap.HashMap[Int32, Int32]?
  /// Names removed according to the wire header.
  priv removed_fields : @hashmap.HashMap[String, Bool]?
  /// Remaining-region handle per version (updated after each chunk read).
  priv inputs : Array[InputRegion]?
  priv last_index_per_chunk : Array[Int32]?
}

///|
/// Byte range fencing one generation chunk on the input. An empty region
/// rejects all reads.
priv struct InputRegion {
  start : Int32
  size : Int32
}

///|
fn InputRegion::empty() -> InputRegion {
  { start: 0, size: 0, }
}

///|
/// Create a reader for data whose *stored* version is 0: fields follow the
/// version byte directly (the metadata may still describe a newer schema —
/// new readers reading old data).
pub fn AdtReader::new_v0(
  metadata : AdtMetadata,
  ctx : DeserializationContext,
) -> AdtReader {
  // Note: metadata may have any version — this constructor is used whenever
  // the *stored* version is 0 (a new reader reading old data), where chunk
  // machinery is not needed.
  {
    metadata,
    ctx,
    stored_version: 0,
    made_optional_at: None,
    removed_fields: None,
    inputs: None,
    last_index_per_chunk: None,
  }
}

///|
/// Create a reader for data stored with `stored_version`. Parses the
/// `stored_version + 1` header entries and slices the input into per-version
/// chunk regions.
pub fn AdtReader::new(
  metadata : AdtMetadata,
  ctx : DeserializationContext,
  stored_version : Int32,
) -> AdtReader raise DesertFailure {
  let made_optional : @hashmap.HashMap[Int32, Int32] = @hashmap.HashMap([])
  let removed : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  // Pass 1: parse the header entries sequentially (they are contiguous
  // varint payloads; chunk data follows the whole header).
  let steps : Array[SerializedEvolutionStep] = []
  for _i in 0..<(stored_version + 1) {
    steps.push(SerializedEvolutionStep::deserialize(ctx))
  }
  // Pass 2: slice the chunk regions sequentially from the current cursor.
  let inputs : Array[InputRegion] = []
  for idx, step in steps {
    match step {
      FieldAddedToNewChunk(size) => {
        let start = ctx.pos()
        ctx.skip(size)
        inputs.push({ start, size, })
      }
      FieldMadeOptionalStep(position) => {
        made_optional.set(position.to_byte(), idx)
        inputs.push(InputRegion::empty())
      }
      FieldRemovedStep(field_name) => {
        removed.set(field_name, true)
        inputs.push(InputRegion::empty())
      }
      UnknownStep => inputs.push(InputRegion::empty())
    }
  }
  let made_optional_at = if made_optional.is_empty() {
    None
  } else {
    Some(made_optional)
  }
  {
    metadata,
    ctx,
    stored_version,
    made_optional_at,
    removed_fields: if removed.is_empty() {
      None
    } else {
      Some(removed)
    },
    inputs: Some(inputs),
    last_index_per_chunk: match made_optional_at {
      Some(_) => {
        let arr : Array[Int32] = []
        for _i in 0..<metadata.evolution_steps.length() {
          arr.push(-1)
        }
        Some(arr)
      }
      None => None
    },
  }
}

///|
/// Read a required field.
///
/// `default` supplies the value for fields that were added after the stored
/// version; without a default such data fails with
/// `FieldWithoutDefaultValueIsMissing`.
pub fn[T : BinaryDeserializer] AdtReader::read_field(
  self : AdtReader,
  field_name : String,
  default : T?,
) -> T raise DesertFailure {
  match self.removed_fields {
    Some(removed) if removed.contains(field_name) =>
      raise FieldRemovedInSerializedVersion(field_name)
    _ => ()
  }
  let chunk = self.metadata.generation_of(field_name)
  let field_position = self.record_field_index(chunk)
  if self.stored_version < chunk {
    match default {
      Some(value) => value
      None => raise FieldWithoutDefaultValueIsMissing(field_name)
    }
  } else {
    let has_inputs = self.push_chunk_region(chunk)
    let result = if self.is_made_optional_on_wire(field_position) {
      // The writer's codec had this field optional; a bare `None` cannot be
      // represented in the non-optional reader type.
      let is_defined = self.ctx.read_u8() != b'\x00'
      if is_defined {
        T::deserialize(self.ctx)
      } else {
        raise NonOptionalFieldSerializedAsNone(field_name)
      }
    } else {
      T::deserialize(self.ctx)
    }
    if has_inputs {
      self.pop_chunk_region(chunk)
    }
    result
  }
}

///|
/// Read an optional field, applying the `FieldMadeOptional` compatibility
/// rules. `default` supplies the whole `Option` for fields added after the
/// stored version.
pub fn[T : BinaryDeserializer] AdtReader::read_optional_field(
  self : AdtReader,
  field_name : String,
  default : T??,
) -> T? raise DesertFailure {
  match self.removed_fields {
    Some(removed) if removed.contains(field_name) => return None
    _ => ()
  }
  let chunk = self.metadata.generation_of(field_name)
  let opt_since = match self.metadata.made_optional_at.get(field_name) {
    Some(version) => version
    None => 0
  }
  let _ = self.record_field_index(chunk)
  if self.stored_version < chunk {
    match default {
      Some(value) => value
      None =>
        raise DeserializationFailure(
          "Field \{field_name} is not in the stream and does not have a default value",
        )
    }
  } else {
    let has_inputs = self.push_chunk_region(chunk)
    let result = if self.stored_version < opt_since {
      // Older writer stored the bare value.
      Some(T::deserialize(self.ctx))
    } else {
      self.ctx.read_optional_value()
    }
    if has_inputs {
      self.pop_chunk_region(chunk)
    }
    result
  }
}

///|
/// Read the coproduct constructor index (the record itself being an enum).
pub fn AdtReader::read_constructor_idx(
  self : AdtReader,
) -> Int32 raise DesertFailure {
  self.ctx.read_var_u32().reinterpret_as_int()
}

///|
fn AdtReader::is_made_optional_on_wire(
  self : AdtReader,
  field_position : FieldPosition,
) -> Bool {
  match self.made_optional_at {
    Some(map) => map.contains(field_position.to_byte())
    None => false
  }
}

///|
fn AdtReader::push_chunk_region(self : AdtReader, chunk : Int32) -> Bool {
  match self.inputs {
    Some(inputs) => {
      let region = inputs[chunk]
      self.ctx.push_region(region.start, region.size)
      true
    }
    None => false
  }
}

///|
fn AdtReader::pop_chunk_region(self : AdtReader, chunk : Int32) -> Unit {
  match self.inputs {
    Some(inputs) => {
      let (start, size) = self.ctx.pop_region()
      inputs[chunk] = { start, size, }
    }
    None => ()
  }
}

///|
fn AdtReader::record_field_index(
  self : AdtReader,
  chunk : Int32,
) -> FieldPosition {
  match self.last_index_per_chunk {
    Some(indices) => {
      let new_index = indices[chunk] + 1
      indices[chunk] = new_index
      FieldPosition::new(chunk, new_index)
    }
    None => FieldPosition::new(0, 0)
  }
}
