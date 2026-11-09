///|
/// Streaming writer for evolved records, the runtime engine behind derived
/// codecs (mirrors desert-rust's `AdtSerializer`).
///
/// For a record with `V` evolution steps (`AdtMetadata::version`):
/// - `new_v0` (V = 0) writes the `0` version byte and fields go straight to
///   the active output — wire-identical to a plain tuple.
/// - `new` (V > 0) writes the version byte, routes every field into the
///   buffer of its generation chunk (`write_field`), and `finish` appends the
///   evolution header followed by the chunk bytes.
///
/// Fields not mentioned in any `FieldAdded` step belong to chunk 0.
pub struct AdtWriter {
  priv metadata : AdtMetadata
  priv ctx : SerializationContext
  /// One buffer per version, `None` until a field is routed there.
  priv buffers : Array[ByteOutput?]
  /// Per-chunk last field position, tracked only when the record has
  /// `FieldMadeOptional` steps (needed to emit their header entries).
  priv last_index_per_chunk : Array[Int32]?
  priv field_indices : @hashmap.HashMap[String, FieldPosition]?
}

///|
/// Create a writer for a version-0 record: writes the version byte `0` and
/// lets fields serialize directly to the active output.
pub fn AdtWriter::new_v0(
  metadata : AdtMetadata,
  ctx : SerializationContext,
) -> AdtWriter raise DesertFailure {
  ctx.write_u8(b'\x00')
  {
    metadata,
    ctx,
    buffers: [],
    last_index_per_chunk: None,
    field_indices: None,
  }
}

///|
/// Create a writer for an evolved record: writes the version byte and
/// prepares the per-generation chunk buffers.
pub fn AdtWriter::new(
  metadata : AdtMetadata,
  ctx : SerializationContext,
) -> AdtWriter raise DesertFailure {
  ctx.write_u8(metadata.version.to_byte())
  let chunk_count = metadata.evolution_steps.length()
  let buffers : Array[ByteOutput?] = []
  for _i in 0..<chunk_count {
    buffers.push(None)
  }
  let last_index_per_chunk = if metadata.contains_field_made_optional {
    Some(
      {
        let arr : Array[Int32] = []
        for _i in 0..<chunk_count {
          arr.push(-1)
        }
        arr
      },
    )
  } else {
    None
  }
  {
    metadata,
    ctx,
    buffers,
    last_index_per_chunk,
    field_indices: if metadata.contains_field_made_optional {
      Some(@hashmap.HashMap([]))
    } else {
      None
    },
  }
}

///|
/// Serialize one field of the record, routing it to its generation's chunk
/// buffer (for evolved records).
pub fn[T : BinarySerializer] AdtWriter::write_field(
  self : AdtWriter,
  field_name : String,
  value : T,
) -> Unit raise DesertFailure {
  let chunk = self.metadata.generation_of(field_name)
  if self.buffers.length() > 0 {
    let buffer = match self.buffers[chunk] {
      Some(existing) => existing
      None => ByteOutput::new()
    }
    let obj : &BinaryOutput = buffer
    self.ctx.push_output(obj)
    BinarySerializer::serialize(value, self.ctx)
    let _ = self.ctx.pop_output()
    self.buffers[chunk] = Some(buffer)
    self.record_field_index(field_name, chunk)
  } else {
    BinarySerializer::serialize(value, self.ctx)
  }
}

///|
/// Write a coproduct constructor index directly to the active output,
/// followed by the case body produced by `serialize_case`.
pub fn AdtWriter::write_constructor(
  self : AdtWriter,
  constructor_idx : UInt32,
  serialize_case : (SerializationContext) -> Unit raise DesertFailure,
) -> Unit raise DesertFailure {
  self.ctx.write_var_u32(constructor_idx)
  serialize_case(self.ctx)
}

///|
/// Append the evolution header and the chunk data (evolved records only;
/// a no-op for version 0).
pub fn AdtWriter::finish(self : AdtWriter) -> Unit raise DesertFailure {
  if self.buffers.length() == 0 {
    return
  }
  for v, step in self.metadata.evolution_steps {
    let serialized : SerializedEvolutionStep = match step {
      InitialVersion | FieldAdded(_) =>
        FieldAddedToNewChunk(chunk_size(self.buffers[v]))
      FieldMadeOptional(name) =>
        match self.field_index_of(name) {
          Some(position) => FieldMadeOptionalStep(position)
          None =>
            if self.metadata.removed_fields.contains(name) {
              FieldRemovedStep(name)
            } else {
              raise UnknownFieldReferenceInEvolutionStep(name)
            }
        }
      FieldRemoved(name) | FieldMadeTransient(name) => FieldRemovedStep(name)
    }
    serialized.serialize(self.ctx)
  }
  for buffer in self.buffers {
    match buffer {
      Some(b) => {
        let bytes = b.to_bytes()
        if bytes.length() > 0 {
          self.ctx.write_bytes(bytes.exact_view())
        }
      }
      None => ()
    }
  }
}

///|
fn chunk_size(buffer : ByteOutput?) -> Int32 {
  match buffer {
    Some(b) => b.length()
    None => 0
  }
}

///|
fn AdtWriter::field_index_of(
  self : AdtWriter,
  field_name : String,
) -> FieldPosition? {
  match self.field_indices {
    Some(indices) => indices.get(field_name)
    None => None
  }
}

///|
fn AdtWriter::record_field_index(
  self : AdtWriter,
  field_name : String,
  chunk : Int32,
) -> Unit {
  match self.last_index_per_chunk {
    Some(indices) => {
      let new_index = indices[chunk] + 1
      indices[chunk] = new_index
      match self.field_indices {
        Some(map) => map.set(field_name, FieldPosition::new(chunk, new_index))
        None => ()
      }
    }
    None => ()
  }
}
