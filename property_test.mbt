///|
fn[T : @desert.BinarySerializer] pser(value : T) -> Bytes {
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
fn[T : @desert.BinaryDeserializer] pdeser(data : Bytes) -> T {
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
fn[T : @desert.BinarySerializer + @desert.BinaryDeserializer + Eq] property_roundtrip(
  value : T,
) -> Bool {
  pdeser(pser(value)) == value
}

///|
test "prop int roundtrip" {
  @quickcheck.check(count=300, (x : Int32) => property_roundtrip(x))
}

///|
test "prop int64 roundtrip" {
  @quickcheck.check(count=300, (x : Int64) => property_roundtrip(x))
}

///|
test "prop byte roundtrip" {
  @quickcheck.check(count=300, (x : Byte) => property_roundtrip(x))
}

///|
test "prop bool roundtrip" {
  @quickcheck.check(count=300, (x : Bool) => property_roundtrip(x))
}

///|
/// Build a valid-Unicode string from arbitrary integer seeds: each seed is
/// mapped onto a valid scalar value (surrogate range excluded), since the
/// quickcheck Char/String generators cover the whole numeric range.
fn valid_string(codes : Array[Int32]) -> String {
  let sb = StringBuilder()
  for seed in codes {
    let base = if seed < 0 { -(seed + 1) } else { seed }
    let mut cp = base % 0x110000
    if cp >= 0xD800 && cp <= 0xDFFF {
      cp = cp - 0x800
    }
    sb.write_char(cp.unsafe_to_char())
  }
  sb.to_string()
}

///|
test "prop string roundtrip" {
  @quickcheck.check(count=300, (codes : Array[Int32]) => {
    property_roundtrip(valid_string(codes))
  })
}

///|
test "prop uint16 roundtrip" {
  @quickcheck.check(count=300, (x : UInt16) => property_roundtrip(x))
}

///|
test "prop uint64 roundtrip" {
  @quickcheck.check(count=300, (x : UInt64) => property_roundtrip(x))
}

///|
test "prop float roundtrip by bits" {
  @quickcheck.check(count=300, (x : Float) => {
    let bits = x.reinterpret_as_uint()
    let back : Float = pdeser(pser(x))
    back.reinterpret_as_uint() == bits
  })
}

///|
test "prop double roundtrip by bits" {
  @quickcheck.check(count=300, (x : Double) => {
    let bits = x.reinterpret_as_uint64()
    let back : Double = pdeser(pser(x))
    back.reinterpret_as_uint64() == bits
  })
}

///|
test "prop option int roundtrip" {
  @quickcheck.check(count=300, (x : Int32?) => property_roundtrip(x))
}

///|
test "prop result roundtrip" {
  @quickcheck.check(count=300, (x : Result[Int32, String]?) => {
    property_roundtrip(x)
  })
}

///|
test "prop array int roundtrip" {
  @quickcheck.check(count=300, (x : Array[Int32]) => property_roundtrip(x))
}

///|
test "prop bytes block roundtrip" {
  @quickcheck.check(count=300, (x : Bytes) => property_roundtrip(x))
}

///|
/// Zigzag varint encoding is a bijection over i32.
test "prop varint i32 bijection" {
  @quickcheck.check(count=300, (x : Int32) => {
    let out = @desert.ByteOutput::new()
    let ctx = @desert.SerializationContext::new(
      out,
      @desert.SerializerState::new(),
      @desert.Options::default(),
    )
    ctx.write_var_i32(x)
    let in_ctx = @desert.DeserializationContext::new(
      @desert.BinaryInput::new(out.to_bytes()),
      @desert.SerializerState::new(),
      @desert.Options::default(),
    )
    in_ctx.read_var_i32() == x
  })
}

///|
test "prop varint u32 bijection" {
  @quickcheck.check(count=300, (x : UInt32) => {
    let out = @desert.ByteOutput::new()
    let ctx = @desert.SerializationContext::new(
      out,
      @desert.SerializerState::new(),
      @desert.Options::default(),
    )
    ctx.write_var_u32(x)
    let in_ctx = @desert.DeserializationContext::new(
      @desert.BinaryInput::new(out.to_bytes()),
      @desert.SerializerState::new(),
      @desert.Options::default(),
    )
    in_ctx.read_var_u32() == x
  })
}

///|
/// UTF-8 transcoding is lossless for valid strings (lone surrogates are
/// substituted on encode, so this property tests constructible text only).
test "prop utf8 transcode identity" {
  @quickcheck.check(count=300, (codes : Array[Int32]) => {
    let s = valid_string(codes)
    let len = @desert.utf8_byte_length(s)
    let buf : FixedArray[Byte] = FixedArray::make(len, b'\x00')
    let written = @desert.write_utf8(s, buf, 0)
    if written != len {
      return false
    }
    @desert.read_utf8(Bytes::from_array(buf).exact_view(end=len)) == s
  })
}

///|
/// Composite evolved record: property-test the ADT engine over arbitrary
/// values.
#derive(Debug, Eq)
struct PropRecord {
  id : Int32
  name : String
  score : Double
  active : Bool
}

///|
pub extend PropRecord with Eq::{not_equal, equal}

///|
pub extend PropRecord with @moonbitlang/core/debug.Debug::{to_repr}

///|
let prop_record_metadata : @desert.AdtMetadata = @desert.AdtMetadata::new([
  @desert.InitialVersion,
])

///|
impl @desert.BinarySerializer for PropRecord with fn serialize(self, ctx) {
  let writer = @desert.AdtWriter::new_v0(prop_record_metadata, ctx)
  writer.write_field("id", self.id)
  writer.write_field("name", self.name)
  writer.write_field("score", self.score)
  writer.write_field("active", self.active)
  writer.finish()
}

///|
impl @desert.BinaryDeserializer for PropRecord with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    @desert.AdtReader::new_v0(prop_record_metadata, ctx)
  } else {
    @desert.AdtReader::new(prop_record_metadata, ctx, stored)
  }
  let id : Int32 = reader.read_field("id", None)
  let name : String = reader.read_field("name", None)
  let score : Double = reader.read_field("score", None)
  let active : Bool = reader.read_field("active", None)
  { id, name, score, active, }
}

///|
test "prop version0 record roundtrip" {
  @quickcheck.check(count=300, (input : (Int32, Array[Int32], Double, Bool)) => {
    let (id, name_codes, score, active) = input
    property_roundtrip(PropRecord::{
      id,
      name: valid_string(name_codes),
      score,
      active,
    })
  })
}
