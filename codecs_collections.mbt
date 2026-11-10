///|
/// Option codec: `0x01` followed by the payload for `Some`, a single `0x00`
/// byte for `None`.
pub impl[T : BinarySerializer] BinarySerializer for T? with fn serialize(
  self,
  ctx,
) {
  match self {
    Some(v) => {
      ctx.write_u8(b'\x01')
      v.serialize(ctx)
    }
    None => ctx.write_u8(b'\x00')
  }
}

///|
pub impl[T : BinaryDeserializer] BinaryDeserializer for T? with fn deserialize(
  ctx,
) {
  match ctx.input.read_u8() {
    b'\x01' => Some(T::deserialize(ctx))
    b'\x00' => None
    other =>
      raise DeserializationFailure(
        "Failed to deserialize Option: invalid tag: \{other.to_int()}",
      )
  }
}

///|
/// Result codec (the stand-in for Scala's `Either`): `0x01` + payload for
/// `Ok` (right), `0x00` + payload for `Err` (left).
pub impl[T : BinarySerializer, E : BinarySerializer] BinarySerializer for Result[
  T,
  E,
] with fn serialize(self, ctx) {
  match self {
    Ok(v) => {
      ctx.write_u8(b'\x01')
      v.serialize(ctx)
    }
    Err(e) => {
      ctx.write_u8(b'\x00')
      e.serialize(ctx)
    }
  }
}

///|
pub impl[T : BinaryDeserializer, E : BinaryDeserializer] BinaryDeserializer for Result[
  T,
  E,
] with fn deserialize(ctx) {
  match ctx.input.read_u8() {
    b'\x01' => Ok(T::deserialize(ctx))
    b'\x00' => Err(E::deserialize(ctx))
    other =>
      raise DeserializationFailure(
        "Failed to deserialize Result: invalid tag: \{other.to_int()}",
      )
  }
}

///|
/// Byte-block codec (`Bytes`): `var_u32(length)` followed by the raw bytes.
///
/// This is the dedicated byte-block format used for byte arrays in the Scala
/// (`Chunk[Byte]`) and Rust (`Vec<u8>`) libraries — note that it uses an
/// *unsigned* varint, unlike the generic collection encoding.
pub impl BinarySerializer for Bytes with fn serialize(self, ctx) {
  ctx.write_var_u32(self.length().reinterpret_as_uint())
  if self.length() > 0 {
    ctx.write_bytes(self.exact_view())
  }
}

///|
pub impl BinaryDeserializer for Bytes with fn deserialize(ctx) {
  let len = ctx.read_var_u32().reinterpret_as_int()
  ctx.input.read_bytes(len)
}

///|
/// Array codec (the generic counted collection form): `var_i32(length)`
/// followed by the element payloads, no separators.
///
/// The deserializer also accepts the unknown-size form (`var_i32(-1)`, then
/// `0x01`-tagged elements terminated by `0x00`), so arrays can read data
/// written from any iterable, matching the cross-collection compatibility of
/// the original libraries.
pub impl[T : BinarySerializer] BinarySerializer for Array[T] with fn serialize(
  self,
  ctx,
) {
  ctx.write_var_i32(self.length())
  for v in self {
    v.serialize(ctx)
  }
}

///|
/// Specialized counted-form serializer for `Array[Int]`: plain loop over
/// `ctx.write_i32` — wire-identical to the generic path (count prefix +
/// 4-byte BE payloads), minus iterator/generic dispatch overhead.
pub impl BinarySerializer for ArrayOfInt with fn serialize(self, ctx) {
  ctx.write_var_i32(self.values.length())
  for v in self.values {
    ctx.write_i32(v)
  }
}

///|
/// Newtype marking an `Array[Int]` with the specialized codec (MoonBit
/// coherence: a second `BinarySerializer` impl cannot be attached to
/// `Array[Int]` itself).
pub struct ArrayOfInt {
  values : Array[Int32]
}

///|
/// Wrap an `Array[Int]` to use the specialized serializer. Deserialization
/// via the plain `Array[Int]` codec accepts the identical bytes, so callers
/// can keep decoding into a plain array.
pub fn ArrayOfInt::new(values : Array[Int32]) -> ArrayOfInt {
  { values, }
}

///|
pub impl[T : BinaryDeserializer] BinaryDeserializer for Array[T] with fn deserialize(
  ctx,
) {
  ctx.read_flexible_array()
}

///|
/// Deserialize an array accepting both wire forms of the generic collection
/// encoding:
/// - counted: `var_i32(n)` followed by `n` element payloads
/// - unknown-size: `var_i32(-1)`, then `0x01` + element for each item,
///   terminated by `0x00`
pub fn[T : BinaryDeserializer] DeserializationContext::read_flexible_array(
  self : DeserializationContext,
) -> Array[T] raise DesertFailure {
  let count = self.read_var_i32()
  if count >= 0 {
    let arr : Array[T] = []
    for _i in 0..<count {
      arr.push(T::deserialize(self))
    }
    arr
  } else if count == -1 {
    let arr : Array[T] = []
    let mut go = true
    while go {
      match self.input.read_u8() {
        b'\x01' => arr.push(T::deserialize(self))
        b'\x00' => go = false
        other =>
          raise DeserializationFailure(
            "Failed to deserialize collection: invalid element tag: \{other.to_int()}",
          )
      }
    }
    arr
  } else {
    raise DeserializationFailure(
      "Failed to deserialize collection: invalid length: \{count}",
    )
  }
}

///|
/// Serialize a lazy iterator using the unknown-size collection form
/// (`var_i32(-1)`, then `0x01` + element per item, terminated by `0x00`).
///
/// Use this when the number of items is not known upfront (streaming); when
/// the size is known, prefer a concrete collection codec, which is more
/// compact (no per-element tag).
pub fn[T : BinarySerializer] SerializationContext::write_iter_unknown_size(
  self : SerializationContext,
  iter : Iter[T],
) -> Unit raise DesertFailure {
  self.write_var_i32(-1)
  for v in iter {
    self.write_u8(b'\x01')
    v.serialize(self)
  }
  self.write_u8(b'\x00')
}

///|
/// HashMap codec: the generic counted collection encoding applied to
/// key/value pairs, where each pair is written as a 2-tuple (`0x00` version
/// byte, then key, then value).
///
/// Entry order is the hash-map iteration order and is *not* canonicalized —
/// byte-for-byte output is only stable for a single implementation; cross
/// implementation compatibility holds because both readers accept any order.
pub impl[K : BinarySerializer, V : BinarySerializer] BinarySerializer for @hashmap.HashMap[
  K,
  V,
] with fn serialize(self, ctx) {
  ctx.write_var_i32(self.length())
  for kv in self.iter() {
    let (k, v) = kv
    ctx.write_u8(b'\x00')
    k.serialize(ctx)
    v.serialize(ctx)
  }
}

///|
pub impl[K : BinaryDeserializer + Hash + Eq, V : BinaryDeserializer] BinaryDeserializer for @hashmap.HashMap[
  K,
  V,
] with fn deserialize(ctx) {
  let count = ctx.read_var_i32()
  if count < 0 {
    raise DeserializationFailure(
      "Failed to deserialize HashMap: invalid length: \{count}",
    )
  }
  let map : @hashmap.HashMap[K, V] = @hashmap.HashMap([])
  for _i in 0..<count {
    match ctx.input.read_u8() {
      b'\x00' => ()
      other =>
        raise DeserializationFailure(
          "Failed to deserialize HashMap: invalid entry tag: \{other.to_int()}",
        )
    }
    let k = BinaryDeserializer::deserialize(ctx)
    let v = BinaryDeserializer::deserialize(ctx)
    map.set(k, v)
  }
  map
}

///|
/// Builtin `Map` codec — identical wire format to the `HashMap` codec: the
/// generic counted collection encoding over key/value pairs, each pair
/// written as a 2-tuple. Entry order is not canonicalized.
pub impl[K : BinarySerializer, V : BinarySerializer] BinarySerializer for Map[
  K,
  V,
] with fn serialize(self, ctx) {
  ctx.write_var_i32(self.length())
  for kv in self.iter() {
    let (k, v) = kv
    ctx.write_u8(b'\x00')
    k.serialize(ctx)
    v.serialize(ctx)
  }
}

///|
pub impl[K : BinaryDeserializer + Hash + Eq, V : BinaryDeserializer] BinaryDeserializer for Map[
  K,
  V,
] with fn deserialize(ctx) {
  let count = ctx.read_var_i32()
  if count < 0 {
    raise DeserializationFailure(
      "Failed to deserialize Map: invalid length: \{count}",
    )
  }
  let map : Map[K, V] = Map([])
  for _i in 0..<count {
    match ctx.input.read_u8() {
      b'\x00' => ()
      other =>
        raise DeserializationFailure(
          "Failed to deserialize Map: invalid entry tag: \{other.to_int()}",
        )
    }
    let k = BinaryDeserializer::deserialize(ctx)
    let v = BinaryDeserializer::deserialize(ctx)
    map.set(k, v)
  }
  map
}

///|
/// HashSet codec — identical wire format to any generic collection: the
/// counted encoding over the elements, accepting both forms on read. Element
/// order is not canonicalized.
pub impl[T : BinarySerializer] BinarySerializer for @hashset.HashSet[T] with fn serialize(
  self,
  ctx,
) {
  ctx.write_var_i32(self.length())
  for v in self.iter() {
    v.serialize(ctx)
  }
}

///|
pub impl[T : BinaryDeserializer + Hash + Eq] BinaryDeserializer for @hashset.HashSet[
  T,
] with fn deserialize(ctx) {
  let elements : Array[T] = ctx.read_flexible_array()
  let set : @hashset.HashSet[T] = @hashset.HashSet([])
  for e in elements {
    set.add(e)
  }
  set
}

///|
pub extend ArrayOfInt with BinarySerializer::{serialize}
