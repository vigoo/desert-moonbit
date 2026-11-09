///|
/// Mini-parser for the `#derive.binary_codec(...)` attribute arguments.
///
/// The MoonBit compiler treats unknown attributes as inert, so the tool
/// parses their raw text itself (same technique as the Golem SDK tools).

///|
pub(all) enum EvolutionIR {
  FieldAddedIR(String, String)
  FieldMadeOptionalIR(String)
  FieldRemovedIR(String)
  FieldMadeTransientIR(String)
}

///|
/// True when the raw attribute text is our derive marker.
pub fn is_binary_codec_attr(raw : String) -> Bool {
  raw == "#desert(binary_codec)" ||
  raw.has_prefix("#desert(binary_codec(") ||
  raw.has_prefix("#desert(binary_codec,")
}

///|
/// Parse the argument list body (the text between the outer parentheses).
pub fn parse_derive_args(body : String) -> DeriveOptions raise CodegenError {
  let options = DeriveOptions::empty()
  // The parenthesized body may start with the literal `binary_codec` token
  // (form: `#derive(binary_codec, ...)`); skip it.
  let trimmed = body.trim().to_owned()
  let args_body = if trimmed == "binary_codec" {
    ""
  } else if trimmed.has_prefix("binary_codec,") {
    trimmed[12:].to_owned()
  } else {
    trimmed
  }
  for arg in split_top_level(args_body) {
    let arg = arg.trim().to_owned()
    if arg == "" {
      continue
    }
    if arg == "transparent" {
      options.transparent = true
    } else if arg == "sorted_constructors" {
      options.sorted_constructors = true
    } else if arg.has_prefix("type_id") {
      match split_kv(arg) {
        Some(value) => options.type_id = Some(unquote(value))
        None => raise CodegenError("type_id must be type_id = \"...\"")
      }
    } else if arg.has_prefix("evolution(") {
      let inner = between_parens(arg)
      for step in split_top_level(inner) {
        options.steps.push(parse_evolution_step(step))
      }
    } else {
      raise CodegenError("unknown derive argument: \{arg}")
    }
  }
  options
}

///|
fn parse_evolution_step(step : String) -> EvolutionIR raise CodegenError {
  let step = step.trim().to_owned()
  if step.has_prefix("FieldAdded(") {
    let parts = split_top_level(between_parens(step))
    if parts.is_empty() {
      raise CodegenError("FieldAdded requires (name, default)")
    }
    let name = unquote(parts[0].trim().to_owned())
    let default = if parts.length() > 1 {
      join_with_commas(parts, 1).trim().to_owned()
    } else {
      raise CodegenError("FieldAdded requires a default expression")
    }
    FieldAddedIR(name, default)
  } else if step.has_prefix("FieldMadeOptional(") {
    FieldMadeOptionalIR(unquote(between_parens(step).trim().to_owned()))
  } else if step.has_prefix("FieldRemoved(") {
    FieldRemovedIR(unquote(between_parens(step).trim().to_owned()))
  } else if step.has_prefix("FieldMadeTransient(") {
    FieldMadeTransientIR(unquote(between_parens(step).trim().to_owned()))
  } else {
    raise CodegenError("unknown evolution step: \{step}")
  }
}

///|
/// Extract the text between the first '(' and its matching ')'.
fn between_parens(s : String) -> String raise CodegenError {
  let start = index_of_char(s, '(')
  let end = match matching_paren(s, start) {
    Some(i) => i
    None => raise CodegenError("unbalanced parentheses in: \{s}")
  }
  s[start + 1:end].to_owned()
}

///|
fn index_of_char(s : String, target : Char) -> Int32 {
  let mut i = 0
  let len = s.length()
  while i < len {
    match s.get_char(i) {
      Some(c) => if c == target { return i }
      None => ()
    }
    i = i + 1
  }
  -1
}

///|
/// Index of the ')' matching the '(' at `open_index`, honoring nesting and
/// string literals.
fn matching_paren(s : String, open_index : Int32) -> Int32? {
  let mut depth = 0
  let mut in_string = false
  let mut i = open_index
  let len = s.length()
  while i < len {
    let c = match s.get_char(i) {
      Some(c) => c
      None => break
    }
    if in_string {
      if c == '\\' {
        i = i + 1
      } else if c == '"' {
        in_string = false
      }
    } else if c == '"' {
      in_string = true
    } else if c == '(' {
      depth = depth + 1
    } else if c == ')' {
      depth = depth - 1
      if depth == 0 {
        return Some(i)
      }
    }
    i = i + 1
  }
  None
}

///|
/// Split on top-level commas (outside parentheses and string literals).
pub fn split_top_level(s : String) -> Array[String] {
  let parts : Array[String] = []
  let sb = StringBuilder()
  let mut depth = 0
  let mut in_string = false
  let mut i = 0
  let len = s.length()
  while i < len {
    let c = match s.get_char(i) {
      Some(c) => c
      None => break
    }
    if in_string {
      sb.write_char(c)
      if c == '\\' && i + 1 < len {
        sb.write_char(
          match s.get_char(i + 1) {
            Some(next) => next
            None => c
          },
        )
        i = i + 1
      } else if c == '"' {
        in_string = false
      }
    } else if c == '"' {
      in_string = true
      sb.write_char(c)
    } else if c == '(' {
      depth = depth + 1
      sb.write_char(c)
    } else if c == ')' {
      depth = depth - 1
      sb.write_char(c)
    } else if c == ',' && depth == 0 {
      parts.push(sb.to_string())
      sb.reset()
    } else {
      sb.write_char(c)
    }
    i = i + 1
  }
  let tail = sb.to_string()
  if tail.trim() != "" {
    parts.push(tail)
  }
  parts
}

///|
/// Split `key = value` at the first top-level '='.
fn split_kv(s : String) -> String? {
  let mut in_string = false
  let mut i = 0
  let len = s.length()
  while i < len {
    let c = match s.get_char(i) {
      Some(c) => c
      None => break
    }
    if in_string {
      if c == '\\' {
        i = i + 1
      } else if c == '"' {
        in_string = false
      }
    } else if c == '"' {
      in_string = true
    } else if c == '=' {
      let v = s[i + 1:].trim().to_owned()
      if v != "" {
        return Some(v)
      }
      return None
    }
    i = i + 1
  }
  None
}

///|
/// Strip surrounding double quotes.
fn unquote(s : String) -> String raise CodegenError {
  let t = s.trim().to_owned()
  if t.has_prefix("\"") && t.has_suffix("\"") && t.length() >= 2 {
    unescape_string(t[1:t.length() - 1].to_owned())
  } else {
    raise CodegenError("expected a quoted string, got: \{t}")
  }
}

///|
/// Process the standard escape sequences of a MoonBit string literal body.
fn unescape_string(s : String) -> String {
  let sb = StringBuilder()
  let len = s.length()
  let mut i = 0
  while i < len {
    match s.get_char(i) {
      Some(c) => {
        if c == '\\' && i + 1 < len {
          match s.get_char(i + 1) {
            Some('\"') => {
              sb.write_char('\"')
              i = i + 1
            }
            Some('\\') => {
              sb.write_char('\\')
              i = i + 1
            }
            Some('n') => {
              sb.write_char('\n')
              i = i + 1
            }
            Some('t') => {
              sb.write_char('\t')
              i = i + 1
            }
            Some(next) => {
              sb.write_char('\\')
              sb.write_char(next)
              i = i + 1
            }
            None => sb.write_char('\\')
          }
        } else {
          sb.write_char(c)
        }
        i = i + 1
      }
      None => i = i + 1
    }
  }
  sb.to_string()
}

///|
/// Join parts[from..] back with ", " (used for default expressions that
/// contain top-level commas, e.g. `FieldAdded("pair", (0, ""))` — such
/// defaults must be parenthesized by the author).
fn join_with_commas(
  parts : Array[String],
  from : Int32,
) -> String raise CodegenError {
  if from >= parts.length() {
    raise CodegenError("missing argument")
  }
  let sb = StringBuilder()
  for i in from..<parts.length() {
    if i > from {
      sb.write_string(", ")
    }
    sb.write_string(parts[i])
  }
  sb.to_string()
}
