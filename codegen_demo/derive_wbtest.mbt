///|
/// End-to-end tests for the codegen pipeline: these codecs are generated
/// into `desert_derive.mbt` by `moon run codegen -- codegen_demo` and must
/// produce the exact wire format of hand-written codecs.

///|
fn[T : @desert.BinarySerializer] gser(value : T) -> Bytes {
  let res : Result[Bytes, @desert.DesertFailure] = Ok(
    @desert.serialize_to_bytes(value),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(b) => b
    Err(f) => abort("serialization failed: \{f}")
  }
}

///|
fn[T : @desert.BinaryDeserializer] gdeser(data : Bytes) -> T {
  let res : Result[T, @desert.DesertFailure] = Ok(
    @desert.deserialize_exhaustive(data),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(v) => v
    Err(f) => abort("deserialization failed: \{f}")
  }
}

///|
test "generated version0 struct matches hand-written wire format" {
  let user : DemoUser = { id: 42, name: "xy", email: None, active: true, }
  // version byte + i32 + string + option tag + bool
  assert_eq(gser(user), b"\x00\x00\x00\x00\x2a\x04\x78\x79\x00\x01")
  let back : DemoUser = gdeser(b"\x00\x00\x00\x00\x2a\x04\x78\x79\x00\x01")
  assert_eq(back.id, 42)
  assert_eq(back.name, "xy")
  assert_eq(back.email, None)
  assert_eq(back.active, true)
}

///|
test "generated evolved struct roundtrip and version byte" {
  let settings : DemoSettings = {
    volume: 5,
    nickname: Some("nick"),
    theme: "dark",
  }
  let bytes = gser(settings)
  // Version 2: two FieldAdded steps + one made-optional.
  assert_eq(bytes[0], b'\x02')
  let back : DemoSettings = gdeser(bytes)
  assert_eq(back.volume, 5)
  assert_eq(back.nickname, Some("nick"))
  assert_eq(back.theme, "dark")
}

///|
test "generated evolved struct reads version0 data with default" {
  // Version-0 payload: volume + bare nickname (pre-FieldMadeOptional).
  // No theme chunk (added later); the reader falls back to its default.
  let old : Bytes = b"\x00\x00\x00\x00\x05\x08\x6e\x69\x63\x6b"
  let value : DemoSettings = gdeser_partial(old)
  assert_eq(value.volume, 5)
  assert_eq(value.nickname, Some("nick"))
  assert_eq(value.theme, "light")
}

///|
test "generated sorted enum assigns ids in sorted order" {
  // Sorted: Circle = 0, Point = 1 (Hidden is transient, no id).
  assert_eq(gser(DemoShape::Point), b"\x00\x01\x00")
  assert_eq(gser(DemoShape::Circle(7)), b"\x00\x00\x00\x00\x00\x00\x07")
  let point : DemoShape = gdeser(b"\x00\x01\x00")
  match point {
    DemoShape::Point => ()
    _ => abort("expected Point")
  }
  let circle : DemoShape = gdeser(b"\x00\x00\x00\x00\x00\x00\x07")
  match circle {
    DemoShape::Circle(v) => assert_eq(v, 7)
    _ => abort("expected Circle")
  }
}

///|
test "generated enum rejects transient constructor and unknown ids" {
  let res : Result[Bytes, @desert.DesertFailure] = Ok(
    @desert.serialize_to_bytes(DemoShape::Hidden("x")),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(@desert.SerializingTransientConstructor("DemoShape.Hidden")) => ()
    _ => abort("expected @desert.SerializingTransientConstructor")
  }
  let res2 : Result[DemoShape, @desert.DesertFailure] = Ok(
    @desert.deserialize_exhaustive(b"\x00\x02\x00"),
  ) catch {
    e => Err(e)
  }
  match res2 {
    Err(@desert.InvalidConstructorId(2, "DemoShape")) => ()
    _ => abort("expected @desert.InvalidConstructorId")
  }
}

///|
test "generated codecs integrate with the registry" {
  // type_id is not set on the demo types; register them manually through
  // the generated impls.
  let registry = @desert.TypeRegistryBuilder::new()
    .register("demo.DemoUser", ctx => {
      let v : DemoUser = @desert.BinaryDeserializer::deserialize(ctx)
      v as &@desert.RegisteredValue
    })
    .freeze()
  let user : DemoUser = { id: 1, name: "n", email: None, active: false, }
  let res : Result[Bytes, @desert.DesertFailure] = Ok(
    @desert.serialize_unknown_to_bytes(user, registry),
  ) catch {
    e => Err(e)
  }
  match res {
    Ok(bytes) => {
      // id 1 + version-0 record payload
      assert_eq(bytes[0], b'\x01')
      assert_eq(bytes[1], b'\x00')
    }
    Err(f) => abort("\{f}")
  }
}

///|
/// Deserialize without the exhaustive check (old-version data has no
/// trailing theme chunk by design).
fn[T : @desert.BinaryDeserializer] gdeser_partial(
  data : Bytes,
) -> T raise @desert.DesertFailure {
  @desert.deserialize_exhaustive(data)
}

///|
test "transient case payload is inert" {
  // Hidden carries a payload that is never serialized; construction is
  // allowed but serialization must fail.
  let hidden = Hidden("secret")
  let res : Result[Bytes, @desert.DesertFailure] = Ok(
    @desert.serialize_to_bytes(hidden),
  ) catch {
    e => Err(e)
  }
  match res {
    Err(@desert.SerializingTransientConstructor("DemoShape.Hidden")) => ()
    _ => abort("expected SerializingTransientConstructor")
  }
}
