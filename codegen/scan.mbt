///|
/// Scan parsed sources for `#derive.binary_codec` targets and build the IR.

///|
fn is_enum(desc : @syntax.TypeDesc) -> Bool {
  match desc {
    @syntax.Variant(_) | @syntax.ExtensibleEnum(_) => true
    _ => false
  }
}

///|
fn is_option_type(ty : @syntax.Type) -> Bool {
  match ty {
    @syntax.Option(..) => true
    @syntax.Name(constr_id~, tys~, ..) =>
      match constr_id.id {
        @syntax.Ident(name~) => name == "Option" && tys.length() == 1
        @syntax.Dot(pkg~, id~) =>
          (pkg == "core" || pkg == "") && id == "Option" && tys.length() == 1
      }
    _ => false
  }
}

///|
fn field_transient_default(
  attrs : @list.List[@attribute.Attribute],
) -> String? raise CodegenError {
  for attr in attrs.to_array() {
    if attr.raw == "#transient" {
      // `#transient` with no argument is not meaningful for serialization;
      // treat it as a null-ish default placeholder.
      return Some("None")
    }
    if attr.raw.has_prefix("#transient(") {
      let inner = parse_between_parens_public(attr.raw)
      return Some(inner)
    }
  }
  None
}

///|
fn parse_struct(
  name : String,
  desc : @syntax.TypeDesc,
  options : DeriveOptions,
) -> StructIR raise CodegenError {
  match desc {
    @syntax.Record(fields~, ..) => {
      let field_irs : Array[FieldIR] = []
      for field in fields.to_array() {
        field_irs.push({
          name: field.name.label,
          is_option: is_option_type(field.ty),
          transient_default: field_transient_default(field.attrs),
          added_default: added_default_of(options.steps, field.name.label),
        })
      }
      if options.transparent && field_irs.length() != 1 {
        raise CodegenError("transparent requires exactly one field: \{name}")
      }
      {
        name,
        fields: field_irs,
        steps: options.steps,
        transparent: options.transparent,
        type_id: options.type_id,
      }
    }
    @syntax.TupleStruct(_) =>
      raise CodegenError(
        "tuple structs are not supported by desert-codegen: \{name}",
      )
    _ =>
      raise CodegenError(
        "expected a struct for #derive.binary_codec, got another kind: \{name}",
      )
  }
}

///|
fn parse_enum(
  name : String,
  constrs : @list.List[@syntax.ConstrDecl],
  options : DeriveOptions,
) -> EnumIR raise CodegenError {
  let cases : Array[CaseIR] = []
  for constr in constrs.to_array() {
    let case_transient = has_raw_attr(constr.attrs, "#desert(transient)")
    let case_steps : Array[EvolutionIR] = []
    let mut case_transparent = false
    for attr in constr.attrs.to_array() {
      if attr.raw == "#desert(transparent)" {
        case_transparent = true
      } else if attr.raw.has_prefix("#desert(evolution(") {
        let body = parse_between_parens_public(attr.raw)
        for step in split_top_level(body) {
          case_steps.push(parse_evolution_step(step))
        }
      } else if attr.raw == "#desert" || attr.raw.has_prefix("#desert(") {
        // Unknown #desert directive on a case: ignore.
      }
    }
    let arity = match constr.args {
      Some(args) => args.length()
      None => 0
    }
    let option_flags : Array[Bool] = []
    match constr.args {
      Some(args) =>
        for arg in args {
          option_flags.push(is_option_type(arg.ty))
        }
      None => ()
    }
    if case_transparent && arity != 1 {
      raise CodegenError(
        "transparent case must have exactly one field: \{name}.\{constr.name.name}",
      )
    }
    cases.push({
      name: constr.name.name,
      arity,
      option_flags,
      steps: case_steps,
      transient: case_transient,
      transparent: case_transparent,
    })
  }
  if options.transparent {
    raise CodegenError("transparent is not supported on enums: \{name}")
  }
  let ordered_cases = if options.sorted_constructors {
    sort_cases_by_name(cases)
  } else {
    cases
  }
  {
    name,
    cases: ordered_cases,
    sorted_constructors: options.sorted_constructors,
    type_id: options.type_id,
  }
}

///|
/// The default expression declared by a FieldAdded step for `field_name`.
fn added_default_of(steps : Array[EvolutionIR], field_name : String) -> String? {
  for step in steps {
    match step {
      FieldAddedIR(name, default) =>
        if name == field_name {
          return Some(default)
        }
      _ => ()
    }
  }
  None
}

///|
fn has_raw_attr(attrs : @list.List[@attribute.Attribute], raw : String) -> Bool {
  for attr in attrs.to_array() {
    if attr.raw == raw {
      return true
    }
  }
  false
}

///|
fn sort_cases_by_name(cases : Array[CaseIR]) -> Array[CaseIR] {
  // Stable insertion sort by case name.
  let sorted : Array[CaseIR] = []
  for c in cases {
    let mut inserted = false
    for i in 0..<sorted.length() {
      if !inserted && c.name.lexical_compare(sorted[i].name) < 0 {
        sorted.insert(i, c)
        inserted = true
        break
      }
    }
    if !inserted {
      sorted.push(c)
    }
  }
  sorted
}

///|
/// Public helper used by the field-attribute reader.
pub fn parse_between_parens_public(s : String) -> String raise CodegenError {
  let start = index_of_char(s, '(')
  if start < 0 {
    raise CodegenError("no parentheses in: \{s}")
  }
  match matching_paren(s, start) {
    Some(end) => s[start + 1:end].to_owned()
    None => raise CodegenError("unbalanced parentheses in: \{s}")
  }
}

///|
/// Walk one parsed source file, returning the derived structs and enums.
pub fn scan_impls(
  impls : @list.List[@syntax.Impl],
) -> (Array[StructIR], Array[EnumIR]) raise CodegenError {
  let structs : Array[StructIR] = []
  let enums : Array[EnumIR] = []
  for impl_ in impls.to_array() {
    match impl_ {
      @syntax.TopTypeDef(type_decl) => {
        let mut found : DeriveOptions? = None
        for attr in type_decl.attrs.to_array() {
          if is_binary_codec_attr(attr.raw) {
            let body = if attr.raw.has_prefix("#desert(binary_codec") {
              parse_between_parens_public(attr.raw)
            } else {
              ""
            }
            found = Some(parse_derive_args(body))
            break
          }
        }
        match found {
          Some(options) => {
            let name = type_decl.tycon
            if is_enum(type_decl.components) && options.steps.length() > 0 {
              raise CodegenError(
                "container-level evolution on enums is not supported (put evolution steps on individual cases instead): \{name}",
              )
            }
            match type_decl.components {
              @syntax.Record(..) =>
                structs.push(parse_struct(name, type_decl.components, options))
              @syntax.Variant(constrs) =>
                enums.push(parse_enum(name, constrs, options))
              @syntax.ExtensibleEnum(Some(constrs)) =>
                enums.push(parse_enum(name, constrs, options))
              _ =>
                raise CodegenError(
                  "#derive.binary_codec requires a struct or enum: \{name}",
                )
            }
          }
          None => ()
        }
      }
      _ => ()
    }
  }
  (structs, enums)
}
