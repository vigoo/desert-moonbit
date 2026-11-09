///|
/// Error raised for invalid derive annotations or inputs.
pub suberror CodegenError {
  CodegenError(String)
}

///|
pub(all) struct DeriveOptions {
  mut transparent : Bool
  mut sorted_constructors : Bool
  mut type_id : String?
  mut steps : Array[EvolutionIR]
}

///|
/// Internal representation of one derived struct.
pub(all) struct StructIR {
  name : String
  fields : Array[FieldIR]
  steps : Array[EvolutionIR]
  transparent : Bool
  type_id : String?
}

///|
pub(all) struct FieldIR {
  name : String
  is_option : Bool
  transient_default : String?
  /// Default expression from a FieldAdded step, if this field has one.
  added_default : String?
}

///|
/// Internal representation of one derived enum (with per-case data).
pub(all) struct EnumIR {
  name : String
  cases : Array[CaseIR]
  sorted_constructors : Bool
  type_id : String?
}

///|
pub(all) struct CaseIR {
  name : String
  arity : Int32
  option_flags : Array[Bool]
  /// Case-level `#desert(evolution(...))` steps.
  steps : Array[EvolutionIR]
  /// Case-level `#desert(transient)` marker.
  transient : Bool
  transparent : Bool
}

///|
pub fn DeriveOptions::empty() -> DeriveOptions {
  { transparent: false, sorted_constructors: false, type_id: None, steps: [], }
}
