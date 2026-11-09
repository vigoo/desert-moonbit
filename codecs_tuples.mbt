///|
/// Tuple codecs.
///
/// On the wire an n-tuple (n >= 2) is written as a version-0 record: a
/// single `0x00` version byte followed by the element payloads. This is
/// byte-compatible with both existing implementations, where tuples share
/// the record encoding and a version-0 struct is wire-identical to a tuple
/// of the same shape (so tuples can be read as structs and vice versa).
///
/// MoonBit has no 1-tuple type; wrap the value in its own type instead.

///|
pub impl[A : BinarySerializer, B : BinarySerializer] BinarySerializer for (A, B) with fn serialize(
  self,
  ctx,
) {
  let (a, b) = self
  ctx.write_u8(b'\x00')
  a.serialize(ctx)
  b.serialize(ctx)
}

///|
pub impl[A : BinaryDeserializer, B : BinaryDeserializer] BinaryDeserializer for (
  A,
  B,
) with fn deserialize(ctx) {
  expect_record_version(ctx)
  (A::deserialize(ctx), B::deserialize(ctx))
}

///|
pub impl[A : BinarySerializer, B : BinarySerializer, C : BinarySerializer] BinarySerializer for (
  A,
  B,
  C,
) with fn serialize(self, ctx) {
  let (a, b, c) = self
  ctx.write_u8(b'\x00')
  a.serialize(ctx)
  b.serialize(ctx)
  c.serialize(ctx)
}

///|
pub impl[A : BinaryDeserializer, B : BinaryDeserializer, C : BinaryDeserializer] BinaryDeserializer for (
  A,
  B,
  C,
) with fn deserialize(ctx) {
  expect_record_version(ctx)
  (A::deserialize(ctx), B::deserialize(ctx), C::deserialize(ctx))
}

///|
pub impl[
  A : BinarySerializer,
  B : BinarySerializer,
  C : BinarySerializer,
  D : BinarySerializer,
] BinarySerializer for (A, B, C, D) with fn serialize(self, ctx) {
  let (a, b, c, d) = self
  ctx.write_u8(b'\x00')
  a.serialize(ctx)
  b.serialize(ctx)
  c.serialize(ctx)
  d.serialize(ctx)
}

///|
pub impl[
  A : BinaryDeserializer,
  B : BinaryDeserializer,
  C : BinaryDeserializer,
  D : BinaryDeserializer,
] BinaryDeserializer for (A, B, C, D) with fn deserialize(ctx) {
  expect_record_version(ctx)
  (
    A::deserialize(ctx),
    B::deserialize(ctx),
    C::deserialize(ctx),
    D::deserialize(ctx),
  )
}

///|
pub impl[
  A : BinarySerializer,
  B : BinarySerializer,
  C : BinarySerializer,
  D : BinarySerializer,
  E : BinarySerializer,
] BinarySerializer for (A, B, C, D, E) with fn serialize(self, ctx) {
  let (a, b, c, d, e) = self
  ctx.write_u8(b'\x00')
  a.serialize(ctx)
  b.serialize(ctx)
  c.serialize(ctx)
  d.serialize(ctx)
  e.serialize(ctx)
}

///|
pub impl[
  A : BinaryDeserializer,
  B : BinaryDeserializer,
  C : BinaryDeserializer,
  D : BinaryDeserializer,
  E : BinaryDeserializer,
] BinaryDeserializer for (A, B, C, D, E) with fn deserialize(ctx) {
  expect_record_version(ctx)
  (
    A::deserialize(ctx),
    B::deserialize(ctx),
    C::deserialize(ctx),
    D::deserialize(ctx),
    E::deserialize(ctx),
  )
}

///|
pub impl[
  A : BinarySerializer,
  B : BinarySerializer,
  C : BinarySerializer,
  D : BinarySerializer,
  E : BinarySerializer,
  F : BinarySerializer,
] BinarySerializer for (A, B, C, D, E, F) with fn serialize(self, ctx) {
  let (a, b, c, d, e, f) = self
  ctx.write_u8(b'\x00')
  a.serialize(ctx)
  b.serialize(ctx)
  c.serialize(ctx)
  d.serialize(ctx)
  e.serialize(ctx)
  f.serialize(ctx)
}

///|
pub impl[
  A : BinaryDeserializer,
  B : BinaryDeserializer,
  C : BinaryDeserializer,
  D : BinaryDeserializer,
  E : BinaryDeserializer,
  F : BinaryDeserializer,
] BinaryDeserializer for (A, B, C, D, E, F) with fn deserialize(ctx) {
  expect_record_version(ctx)
  (
    A::deserialize(ctx),
    B::deserialize(ctx),
    C::deserialize(ctx),
    D::deserialize(ctx),
    E::deserialize(ctx),
    F::deserialize(ctx),
  )
}

///|
/// Record-shaped values (tuples, and later derived records) start with a
/// version byte; version 0 means "no evolution header, fields follow".
/// Non-zero versions belong to the evolution machinery and are rejected by
/// plain record readers.
fn expect_record_version(
  ctx : DeserializationContext,
) -> Unit raise DesertFailure {
  match ctx.input.read_u8() {
    b'\x00' => ()
    other =>
      raise DeserializationFailure(
        "Unsupported record version: \{other.to_int()} (evolution support is not enabled for this type)",
      )
  }
}
