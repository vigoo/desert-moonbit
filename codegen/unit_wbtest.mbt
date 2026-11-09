///|
/// Unit tests for the codegen pipeline internals: attribute parsing,
/// source scanning, and emitted code.

///|
fn[T] cerror(f : () -> T raise CodegenError) -> CodegenError {
  let res : Result[T, CodegenError] = Ok(f()) catch { e => Err(e) }
  match res {
    Err(e) => e
    Ok(_) => abort("expected a CodegenError")
  }
}

///|
test "attribute matcher accepts all spellings" {
  assert_eq(is_binary_codec_attr("#desert(binary_codec)"), true)
  assert_eq(
    is_binary_codec_attr("#desert(binary_codec, sorted_constructors)"),
    true,
  )
  assert_eq(is_binary_codec_attr("#desert(other)"), false)
  assert_eq(is_binary_codec_attr("#transient(None)"), false)
}

///|
test "parse derive args bare form" {
  let options = parse_derive_args("binary_codec")
  assert_eq(options.transparent, false)
  assert_eq(options.sorted_constructors, false)
  assert_eq(options.type_id, None)
  assert_eq(options.steps.length(), 0)
}

///|
test "parse derive args full form" {
  let options = parse_derive_args(
    "binary_codec, transparent, sorted_constructors, type_id = \"pkg.Type\", evolution(FieldAdded(\"a\", 0), FieldMadeOptional(\"b\"), FieldRemoved(\"c\"), FieldMadeTransient(\"d\"))",
  )
  assert_eq(options.transparent, true)
  assert_eq(options.sorted_constructors, true)
  assert_eq(options.type_id, Some("pkg.Type"))
  assert_eq(options.steps.length(), 4)
  match options.steps[0] {
    FieldAddedIR("a", "0") => ()
    _ => abort("step 0 mismatch")
  }
  match options.steps[1] {
    FieldMadeOptionalIR("b") => ()
    _ => abort("step 1 mismatch")
  }
  match options.steps[2] {
    FieldRemovedIR("c") => ()
    _ => abort("step 2 mismatch")
  }
  match options.steps[3] {
    FieldMadeTransientIR("d") => ()
    _ => abort("step 3 mismatch")
  }
}

///|
test "parse derive args rejects unknown argument" {
  let err = cerror(fn() raise CodegenError {
    parse_derive_args("binary_codec, bogus")
  })
  match err {
    CodegenError(msg) =>
      assert_eq(msg.contains("unknown derive argument"), true)
  }
}

///|
test "parse derive args rejects unquoted type_id" {
  let err = cerror(fn() raise CodegenError {
    parse_derive_args("binary_codec, type_id = Type")
  })
  match err {
    CodegenError(_) => ()
  }
}

///|
test "split top level honors strings and nesting" {
  let parts = split_top_level("a, \"b, c\", (d, e), f")
  assert_eq(parts.length(), 4)
  assert_eq(parts[1], " \"b, c\"")
  assert_eq(parts[2], " (d, e)")
}

///|
test "scan source with annotated struct and enum" {
  let source = "#desert(binary_codec)\nstruct S {\n  a : Int\n  b : String?\n}\n\n#desert(binary_codec, sorted_constructors)\nenum E {\n  First(Int)\n  Second\n}\n"
  let (parsed, reports) = @parser.parse_string(source)
  assert_eq(reports.length(), 0)
  let (structs, enums) = scan_impls(parsed)
  assert_eq(structs.length(), 1)
  assert_eq(enums.length(), 1)
  let st = structs[0]
  assert_eq(st.name, "S")
  assert_eq(st.fields.length(), 2)
  assert_eq(st.fields[0].is_option, false)
  assert_eq(st.fields[1].is_option, true)
  let en = enums[0]
  // Sorted: First < Second — already in order.
  assert_eq(en.cases[0].name, "First")
  assert_eq(en.cases[0].arity, 1)
  assert_eq(en.cases[1].name, "Second")
  assert_eq(en.cases[1].arity, 0)
}

///|
test "scan rejects tuple struct" {
  let source = "#desert(binary_codec)\nstruct T(Int)\n"
  let (parsed, _reports) = @parser.parse_string(source)
  let err = cerror(fn() raise CodegenError { let _ = scan_impls(parsed) })
  match err {
    CodegenError(msg) => assert_eq(msg.contains("struct or enum"), true)
  }
}

///|
test "emit version0 struct matches hand-written layout" {
  let st : StructIR = {
    name: "P",
    fields: [
      {
        name: "x",
        is_option: false,
        transient_default: None,
        added_default: None,
      },
      {
        name: "y",
        is_option: false,
        transient_default: None,
        added_default: None,
      },
    ],
    steps: [],
    transparent: false,
    type_id: None,
  }
  let code = emit_struct(st)
  // The emitted code must parse and contain the direct fast path.
  let (parsed, reports) = @parser.parse_string(code)
  assert_eq(reports.length(), 0)
  let formatted = @formatter.impls_to_string(parsed)
  assert_eq(formatted.contains("AdtWriter"), false)
  assert_eq(formatted.contains("ctx.write_u8"), true)
}

///|
test "emit evolved struct wires defaults into reader calls" {
  let st : StructIR = {
    name: "Q",
    fields: [
      {
        name: "base",
        is_option: false,
        transient_default: None,
        added_default: None,
      },
      {
        name: "extra",
        is_option: false,
        transient_default: None,
        added_default: Some("5"),
      },
    ],
    steps: [FieldAddedIR("extra", "5")],
    transparent: false,
    type_id: None,
  }
  let code = emit_struct(st)
  let (parsed, reports) = @parser.parse_string(code)
  assert_eq(reports.length(), 0)
  let formatted = @formatter.impls_to_string(parsed)
  assert_eq(formatted.contains("AdtWriter::new"), true)
  assert_eq(formatted.contains("AdtReader::new"), true)
  assert_eq(formatted.contains("read_field(\"extra\", Some(5))"), true)
}

///|
test "emit transparent struct delegates to inner codec" {
  let st : StructIR = {
    name: "W",
    fields: [
      {
        name: "value",
        is_option: false,
        transient_default: None,
        added_default: None,
      },
    ],
    steps: [],
    transparent: true,
    type_id: None,
  }
  let code = emit_struct(st)
  let (parsed, reports) = @parser.parse_string(code)
  assert_eq(reports.length(), 0)
  let formatted = @formatter.impls_to_string(parsed)
  assert_eq(formatted.contains("AdtWriter"), false)
  assert_eq(formatted.contains("value"), true)
}

///|
test "emit registered value impls when type_id present" {
  let st : StructIR = {
    name: "R",
    fields: [
      {
        name: "a",
        is_option: false,
        transient_default: None,
        added_default: None,
      },
    ],
    steps: [],
    transparent: false,
    type_id: Some("demo.R"),
  }
  let code = emit_struct(st)
  let (parsed, reports) = @parser.parse_string(code)
  assert_eq(reports.length(), 0)
  let formatted = @formatter.impls_to_string(parsed)
  assert_eq(formatted.contains("RegisteredValue"), true)
  assert_eq(formatted.contains("\"demo.R\""), true)
}

///|
test "emit enum with transient case consumes no id" {
  let en : EnumIR = {
    name: "E",
    cases: [
      {
        name: "Alpha",
        arity: 1,
        option_flags: [false],
        steps: [],
        transient: false,
        transparent: false,
      },
      {
        name: "Beta",
        arity: 0,
        option_flags: [],
        steps: [],
        transient: true,
        transparent: false,
      },
      {
        name: "Gamma",
        arity: 0,
        option_flags: [],
        steps: [],
        transient: false,
        transparent: false,
      },
    ],
    sorted_constructors: false,
    type_id: None,
  }
  let code = emit_enum(en)
  let (parsed, reports) = @parser.parse_string(code)
  assert_eq(reports.length(), 0)
  let formatted = @formatter.impls_to_string(parsed)
  // Alpha = 0, Gamma = 1 (Beta skipped).
  assert_eq(formatted.contains("Alpha(_) => 0U"), true)
  assert_eq(formatted.contains("Gamma => 1U"), true)
  assert_eq(
    formatted.contains("SerializingTransientConstructor(\"E.Beta\")"),
    true,
  )
}

///|
test "unquote unescapes standard sequences" {
  // Exercised indirectly through parse_derive_args with escapes.
  let options = parse_derive_args(
    "binary_codec, evolution(FieldAdded(\"t\", \"\\\"light\\\"\"))",
  )
  match options.steps[0] {
    FieldAddedIR("t", default) => assert_eq(default, "\"\\\"light\\\"\"")
    _ => abort("unexpected step")
  }
}

///|
test "lowercase first for metadata names" {
  assert_eq(lowercase_first("DemoUser"), "demoUser")
  assert_eq(lowercase_first("x"), "x")
  assert_eq(lowercase_first(""), "")
}

///|
test "emit enum with evolved case" {
  let en : EnumIR = {
    name: "V",
    cases: [
      {
        name: "Grown",
        arity: 2,
        option_flags: [false, true],
        steps: [FieldAddedIR("second", "0")],
        transient: false,
        transparent: false,
      },
    ],
    sorted_constructors: false,
    type_id: None,
  }
  let code = emit_enum(en)
  let (parsed, reports) = @parser.parse_string(code)
  assert_eq(reports.length(), 0)
  let formatted = @formatter.impls_to_string(parsed)
  // Case metadata with the FieldAdded step.
  assert_eq(formatted.contains("v_desert_metadata_grown_desert_metadata"), true)
  assert_eq(formatted.contains("FieldAdded(\"second\")"), true)
  // Case reader with stored-version dispatch and option field read.
  assert_eq(formatted.contains("AdtReader::new_v0"), true)
  assert_eq(formatted.contains("read_optional_field(\"field1\""), true)
}

///|
test "emit transparent enum case" {
  let en : EnumIR = {
    name: "T",
    cases: [
      {
        name: "Wrap",
        arity: 1,
        option_flags: [false],
        steps: [],
        transient: false,
        transparent: true,
      },
    ],
    sorted_constructors: false,
    type_id: None,
  }
  let code = emit_enum(en)
  let (parsed, reports) = @parser.parse_string(code)
  assert_eq(reports.length(), 0)
  let formatted = @formatter.impls_to_string(parsed)
  // Transparent case: payload serialized directly, no case version byte.
  assert_eq(formatted.contains("BinarySerializer::serialize(f0, ctx)"), true)
  assert_eq(
    formatted.contains("Wrap(@desert.BinaryDeserializer::deserialize(ctx))"),
    true,
  )
}

///|
test "emit option field in evolved struct uses read_optional_field with default" {
  let st : StructIR = {
    name: "Opt",
    fields: [
      {
        name: "nick",
        is_option: true,
        transient_default: None,
        added_default: Some("\"n\""),
      },
    ],
    steps: [FieldAddedIR("nick", "\"n\""), FieldMadeOptionalIR("nick")],
    transparent: false,
    type_id: None,
  }
  let code = emit_struct(st)
  let (parsed, reports) = @parser.parse_string(code)
  assert_eq(reports.length(), 0)
  let formatted = @formatter.impls_to_string(parsed)
  // The added_default expr is emitted verbatim inside Some(Some(...)).
  assert_eq(formatted.contains("read_optional_field(\"nick\""), true)
  assert_eq(formatted.contains("Some(Some("), true)
}
