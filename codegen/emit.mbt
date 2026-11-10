///|
/// Emit MoonBit source for derived codecs. The generated code mirrors the
/// hand-written codecs in the desert library: version byte + direct field
/// writes for version 0, the AdtWriter/AdtReader engine for evolved records.

///|
pub fn emit_struct(st : StructIR) -> String {
  let sb = StringBuilder()
  emit_struct_metadata(st, sb)
  if !st.transparent {
    emit_struct_serializer(st, sb)
  }
  emit_struct_deserializer(st, sb)
  if st.type_id is Some(id) {
    emit_registered_value(st.name, id, sb)
  }
  sb.to_string()
}

///|
pub fn emit_enum(en : EnumIR) -> String {
  let sb = StringBuilder()
  for case in en.cases {
    if case.steps.length() > 0 {
      emit_case_metadata(en.name, case, sb)
    }
  }
  emit_enum_serializer(en, sb)
  emit_enum_deserializer(en, sb)
  if en.type_id is Some(id) {
    emit_registered_value(en.name, id, sb)
  }
  sb.to_string()
}

///|
fn emit_registered_value(
  name : String,
  type_id : String,
  sb : StringBuilder,
) -> Unit {
  sb.write_string("///|\nimpl @desert.RegisteredValue for ")
  sb.write_string(name)
  sb.write_string(" with registered_type_name(_self) {\n  \"")
  sb.write_string(type_id)
  sb.write_string("\"\n}\n\n///|\nimpl @desert.RegisteredValue for ")
  sb.write_string(name)
  sb.write_string(
    " with serialize_registered(self, ctx) {\n  @desert.BinarySerializer::serialize(self, ctx)\n}\n\n",
  )
}

///|
/// The metadata value: always emitted so both the V0 reader path and the
/// evolved path share one definition.
fn emit_struct_metadata(st : StructIR, sb : StringBuilder) -> Unit {
  sb.write_string("///|\nlet ")
  sb.write_string(metadata_ref(st.name))
  sb.write_string(
    " : @desert.AdtMetadata = @desert.AdtMetadata::new([\n  @desert.InitialVersion",
  )
  for step in st.steps {
    sb.write_string(",\n  ")
    write_evolution_step(step, sb)
  }
  sb.write_string(",\n])\n\n")
}

///|
fn emit_case_metadata(
  type_name : String,
  case : CaseIR,
  sb : StringBuilder,
) -> Unit {
  sb.write_string("///|\nlet ")
  sb.write_string(
    metadata_ref(type_name) +
    "_" +
    lowercase_first(case.name) +
    "_desert_metadata",
  )
  sb.write_string(
    " : @desert.AdtMetadata = @desert.AdtMetadata::new([\n  @desert.InitialVersion",
  )
  for step in case.steps {
    sb.write_string(",\n  ")
    write_evolution_step(step, sb)
  }
  sb.write_string(",\n])\n\n")
}

///|
fn write_evolution_step(step : EvolutionIR, sb : StringBuilder) -> Unit {
  match step {
    FieldAddedIR(name, _default) => {
      sb.write_string("@desert.FieldAdded(\"")
      sb.write_string(name)
      sb.write_string("\")")
    }
    FieldMadeOptionalIR(name) => {
      sb.write_string("@desert.FieldMadeOptional(\"")
      sb.write_string(name)
      sb.write_string("\")")
    }
    FieldRemovedIR(name) => {
      sb.write_string("@desert.FieldRemoved(\"")
      sb.write_string(name)
      sb.write_string("\")")
    }
    FieldMadeTransientIR(name) => {
      sb.write_string("@desert.FieldMadeTransient(\"")
      sb.write_string(name)
      sb.write_string("\")")
    }
  }
}

///|
fn emit_struct_serializer(st : StructIR, sb : StringBuilder) -> Unit {
  sb.write_string("///|\nimpl @desert.BinarySerializer for ")
  sb.write_string(st.name)
  if st.transparent {
    // Transparent: the single field's codec is the whole encoding.
    let field = st.fields[0]
    sb.write_string(
      " with serialize(self, ctx) {\n  @desert.BinarySerializer::serialize(self.",
    )
    sb.write_string(field.name)
    sb.write_string(", ctx)\n}\n\n")
  } else if st.steps.length() == 0 {
    sb.write_string(" with serialize(self, ctx) {\n  ctx.write_u8(b'\\x00')\n")
    for field in st.fields {
      if field.transient_default is Some(_) {
        continue
      }
      sb.write_string("  @desert.BinarySerializer::serialize(self.")
      sb.write_string(field.name)
      sb.write_string(", ctx)\n")
    }
    sb.write_string("}\n\n")
  } else {
    sb.write_string(
      " with serialize(self, ctx) {\n  let writer = @desert.AdtWriter::new(",
    )
    sb.write_string(metadata_ref(st.name))
    sb.write_string(", ctx)\n")
    for field in st.fields {
      if field.transient_default is Some(_) {
        continue
      }
      sb.write_string("  writer.write_field(\"")
      sb.write_string(field.name)
      sb.write_string("\", self.")
      sb.write_string(field.name)
      sb.write_string(")\n")
    }
    sb.write_string("  writer.finish()\n}\n\n")
  }
}

///|
fn emit_struct_deserializer(st : StructIR, sb : StringBuilder) -> Unit {
  sb.write_string("///|\nimpl @desert.BinaryDeserializer for ")
  sb.write_string(st.name)
  if st.transparent {
    let field = st.fields[0]
    sb.write_string(" with deserialize(ctx) {\n  { ")
    sb.write_string(field.name)
    sb.write_string(": @desert.BinaryDeserializer::deserialize(ctx) }\n}\n\n")
  } else if st.steps.length() == 0 {
    sb.write_string(
      " with deserialize(ctx) {\n  let stored = ctx.read_u8().to_int()\n  if stored == 0 {\n    {\n",
    )
    for field in st.fields {
      sb.write_string("      ")
      sb.write_string(field.name)
      sb.write_string(": ")
      write_field_read(field, sb)
      sb.write_string(",\n")
    }
    sb.write_string(
      "    }\n  } else {\n    let reader = @desert.AdtReader::new(",
    )
    sb.write_string(metadata_ref(st.name))
    sb.write_string(", ctx, stored)\n    {\n")
    for field in st.fields {
      if field.transient_default is Some(default) {
        sb.write_string("      ")
        sb.write_string(field.name)
        sb.write_string(": ")
        sb.write_string(default)
        sb.write_string(",\n")
        continue
      }
      sb.write_string("      ")
      sb.write_string(field.name)
      sb.write_string(": ")
      write_reader_call(field, sb)
      sb.write_string(",\n")
    }
    sb.write_string("    }\n  }\n}\n\n")
  } else {
    sb.write_string(
      " with deserialize(ctx) {\n  let stored = ctx.read_u8().to_int()\n  let reader = if stored == 0 {\n    @desert.AdtReader::new_v0(",
    )
    sb.write_string(metadata_ref(st.name))
    sb.write_string(", ctx)\n  } else {\n    @desert.AdtReader::new(")
    sb.write_string(metadata_ref(st.name))
    sb.write_string(", ctx, stored)\n  }\n  {\n")
    for field in st.fields {
      if field.transient_default is Some(default) {
        sb.write_string("    ")
        sb.write_string(field.name)
        sb.write_string(": ")
        sb.write_string(default)
        sb.write_string(",\n")
        continue
      }
      sb.write_string("    ")
      sb.write_string(field.name)
      sb.write_string(": ")
      write_reader_call(field, sb)
      sb.write_string(",\n")
    }
    sb.write_string("  }\n}\n\n")
  }
}

///|
fn write_field_read(field : FieldIR, sb : StringBuilder) -> Unit {
  if field.transient_default is Some(default) {
    sb.write_string(default)
  } else if field.is_option {
    sb.write_string("@desert.BinaryDeserializer::deserialize(ctx)")
  } else {
    sb.write_string("@desert.BinaryDeserializer::deserialize(ctx)")
  }
}

///|
fn write_reader_call(field : FieldIR, sb : StringBuilder) -> Unit {
  if field.is_option {
    sb.write_string("reader.read_optional_field(\"")
    sb.write_string(field.name)
    sb.write_string("\", ")
    write_default_arg(field.added_default, true, sb)
    sb.write_string(")")
  } else {
    sb.write_string("reader.read_field(\"")
    sb.write_string(field.name)
    sb.write_string("\", ")
    write_default_arg(field.added_default, false, sb)
    sb.write_string(")")
  }
}

///|
/// Emit the default argument: `Some(expr)` for read_field, `Some(Some(expr))`
/// for read_optional_field, or plain `None` without a default.
fn write_default_arg(
  default : String?,
  wrap_option : Bool,
  sb : StringBuilder,
) -> Unit {
  match default {
    Some(expr) => {
      sb.write_string("Some(")
      if wrap_option {
        sb.write_string("Some(")
        sb.write_string(expr)
        sb.write_string(")")
      } else {
        sb.write_string(expr)
      }
      sb.write_string(")")
    }
    None => sb.write_string("None")
  }
}

///|
fn case_ctor_pattern(case : CaseIR, sb : StringBuilder) -> Unit {
  sb.write_string(case.name)
  if case.arity > 0 {
    sb.write_string("(")
    for i in 0..<case.arity {
      if i > 0 {
        sb.write_string(", ")
      }
      sb.write_string("f")
      sb.write_string(i.to_string())
    }
    sb.write_string(")")
  }
}

///|
/// Pattern for the constructor-index match: payloads are not inspected.
fn case_ctor_pattern_wildcard(case : CaseIR, sb : StringBuilder) -> Unit {
  sb.write_string(case.name)
  if case.arity > 0 {
    sb.write_string("(")
    for i in 0..<case.arity {
      if i > 0 {
        sb.write_string(", ")
      }
      sb.write_string("_")
    }
    sb.write_string(")")
  }
}

///|
fn emit_enum_serializer(en : EnumIR, sb : StringBuilder) -> Unit {
  sb.write_string("///|\nimpl @desert.BinarySerializer for ")
  sb.write_string(en.name)
  sb.write_string(
    " with serialize(self, ctx) {\n  ctx.write_u8(b'\\x00')\n  let idx : Int32 = match self {\n",
  )
  let mut idx = 0
  for case in en.cases {
    if case.transient {
      continue
    }
    sb.write_string("    ")
    case_ctor_pattern_wildcard(case, sb)
    sb.write_string(" => ")
    sb.write_string(idx.to_string())
    sb.write_string("\n")
    idx = idx + 1
  }
  for case in en.cases {
    if case.transient {
      sb.write_string("    ")
      case_ctor_pattern_wildcard(case, sb)
      sb.write_string(" => raise @desert.SerializingTransientConstructor(\"")
      sb.write_string(en.name)
      sb.write_string(".")
      sb.write_string(case.name)
      sb.write_string("\")\n")
    }
  }
  sb.write_string(
    "  }\n  ctx.write_var_u32(idx.reinterpret_as_uint())\n  match self {\n",
  )
  for case in en.cases {
    if case.transient {
      sb.write_string("    ")
      case_ctor_pattern_wildcard(case, sb)
      sb.write_string(" => raise @desert.SerializingTransientConstructor(\"")
      sb.write_string(en.name)
      sb.write_string(".")
      sb.write_string(case.name)
      sb.write_string("\")\n")
      continue
    }
    sb.write_string("    ")
    case_ctor_pattern(case, sb)
    sb.write_string(" => {\n")
    if case.transparent {
      if case.arity == 0 {
        // Transparent unit case: the constructor index is the entire payload.
      } else {
        // Payload is the single inner value, no case version byte.
        sb.write_string("      @desert.BinarySerializer::serialize(f0, ctx)\n")
      }
    } else if case.steps.length() == 0 {
      sb.write_string("      ctx.write_u8(b'\\x00')\n")
      for i in 0..<case.arity {
        sb.write_string("      @desert.BinarySerializer::serialize(f")
        sb.write_string(i.to_string())
        sb.write_string(", ctx)\n")
      }
    } else {
      sb.write_string("      let case_writer = @desert.AdtWriter::new(")
      sb.write_string(
        metadata_ref(en.name) +
        "_" +
        lowercase_first(case.name) +
        "_desert_metadata",
      )
      sb.write_string(", ctx)\n")
      for i in 0..<case.arity {
        sb.write_string("      case_writer.write_field(\"field")
        sb.write_string(i.to_string())
        sb.write_string("\", f")
        sb.write_string(i.to_string())
        sb.write_string(")\n")
      }
      sb.write_string("      case_writer.finish()\n")
    }
    sb.write_string("    }\n")
  }
  sb.write_string("  }\n}\n\n")
}

///|
fn emit_enum_deserializer(en : EnumIR, sb : StringBuilder) -> Unit {
  sb.write_string("///|\nimpl @desert.BinaryDeserializer for ")
  sb.write_string(en.name)
  sb.write_string(
    " with deserialize(ctx) {\n  let enum_stored = ctx.read_u8().to_int()\n  if enum_stored != 0 {\n    raise @desert.DeserializationFailure(\"Enum \\\"",
  )
  sb.write_string(en.name)
  sb.write_string(
    "\\\" was written with container evolution, which this codec does not support\")\n  }\n  let idx = ctx.read_var_u32().reinterpret_as_int()\n  match idx {\n",
  )
  let mut idx = 0
  for case in en.cases {
    if case.transient {
      continue
    }
    sb.write_string("    ")
    sb.write_string(idx.to_string())
    sb.write_string(" => {\n")
    if case.transparent {
      sb.write_string("      ")
      sb.write_string(case.name)
      if case.arity > 0 {
        sb.write_string("(@desert.BinaryDeserializer::deserialize(ctx))")
      }
      sb.write_string("\n")
    } else if case.steps.length() == 0 {
      sb.write_string(
        "      let case_stored = ctx.read_u8().to_int()\n      if case_stored != 0 {\n        raise @desert.DeserializationFailure(\"Case \\\"",
      )
      sb.write_string(case.name)
      sb.write_string(
        "\\\" was written with evolution steps, which this codec does not support\")\n      }\n      ",
      )
      sb.write_string(case.name)
      if case.arity > 0 {
        sb.write_string("(")
        for i in 0..<case.arity {
          if i > 0 {
            sb.write_string(", ")
          }
          sb.write_string("@desert.BinaryDeserializer::deserialize(ctx)")
        }
        sb.write_string(")")
      }
      sb.write_string("\n")
    } else {
      sb.write_string(
        "      let case_stored = ctx.read_u8().to_int()\n      let reader = if case_stored == 0 {\n        @desert.AdtReader::new_v0(",
      )
      sb.write_string(
        metadata_ref(en.name) +
        "_" +
        lowercase_first(case.name) +
        "_desert_metadata",
      )
      sb.write_string(", ctx)\n      } else {\n        @desert.AdtReader::new(")
      sb.write_string(
        metadata_ref(en.name) +
        "_" +
        lowercase_first(case.name) +
        "_desert_metadata",
      )
      sb.write_string(", ctx, case_stored)\n      }\n      ")
      sb.write_string(case.name)
      if case.arity > 0 {
        sb.write_string("(")
        for i in 0..<case.arity {
          if i > 0 {
            sb.write_string(", ")
          }
          if case.option_flags[i] {
            sb.write_string("reader.read_optional_field(\"field")
            sb.write_string(i.to_string())
            sb.write_string("\", None)")
          } else {
            sb.write_string("reader.read_field(\"field")
            sb.write_string(i.to_string())
            sb.write_string("\", None)")
          }
        }
        sb.write_string(")")
      }
      sb.write_string("\n")
    }
    sb.write_string("    }\n")
    idx = idx + 1
  }
  sb.write_string("    other => raise @desert.InvalidConstructorId(other, \"")
  sb.write_string(en.name)
  sb.write_string("\")\n  }\n}\n\n")
}

///|
/// Top-level `let` names must start lowercase.
pub fn lowercase_first(s : String) -> String {
  if s.is_empty() {
    return s
  }
  let first = match s.get_char(0) {
    Some(c) => c
    None => return s
  }
  let lowered = match first.to_int() {
    cp if cp >= 'A'.to_int() && cp <= 'Z'.to_int() => (cp + 32).unsafe_to_char()
    _ => first
  }
  let sb = StringBuilder()
  sb.write_char(lowered)
  for i in 1..<s.length() {
    match s.get_char(i) {
      Some(c) => sb.write_char(c)
      None => ()
    }
  }
  sb.to_string()
}

///|
pub fn metadata_ref(type_name : String) -> String {
  lowercase_first(type_name) + "_desert_metadata"
}
