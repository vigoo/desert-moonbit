///|
/// A plain record, no evolution. Generated codec must produce the same
/// bytes as a hand-written version-0 record.
#desert(binary_codec, type_id="demo.DemoUser")
struct DemoUser {
  id : Int32
  name : String
  email : String?
  active : Bool
}

///|
/// An evolved record: version 2.
#desert(binary_codec, evolution(FieldAdded("theme", "light"), FieldMadeOptional("nickname")))
struct DemoSettings {
  volume : Int32
  nickname : String?
  theme : String
}

///|
/// A sorted-constructors enum with a transient case.
#desert(binary_codec, sorted_constructors)
enum DemoShape {
  Circle(Int32)
  Point
  #desert(transient)
  Hidden(String)
}
