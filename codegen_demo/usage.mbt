///|
/// Public entry point exercising the generated codecs from within the
/// package (keeps the generated trait impls "used").
pub fn demo_user_roundtrip(
  user : DemoUser,
) -> DemoUser raise @desert.DesertFailure {
  let bytes = @desert.serialize_to_bytes(user)
  @desert.deserialize_exhaustive(bytes)
}

///|
pub fn demo_settings_roundtrip(
  settings : DemoSettings,
) -> DemoSettings raise @desert.DesertFailure {
  let bytes = @desert.serialize_to_bytes(settings)
  @desert.deserialize_exhaustive(bytes)
}

///|
pub fn demo_shape_roundtrip(
  shape : DemoShape,
) -> DemoShape raise @desert.DesertFailure {
  let bytes = @desert.serialize_to_bytes(shape)
  @desert.deserialize_exhaustive(bytes)
}
