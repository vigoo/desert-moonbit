///|
/// Micro benchmarks for the hot paths, following the core library's
/// `test "bench ... total=N"` convention. Run with
/// `moon test --bench` (or `moon test -p vigoo/desert --bench`).

///|
/// The golden-model-like record used by the structural benchmarks.
#derive(Eq)
struct BenchRecord {
  id : Int32
  name : String
  score : Double
  active : Bool
  tags : Array[String]
}

///|
let bench_record_metadata : AdtMetadata = AdtMetadata::new([
  InitialVersion,
  FieldAdded("tags"),
])

///|
impl BinarySerializer for BenchRecord with fn serialize(self, ctx) {
  let writer = AdtWriter::new(bench_record_metadata, ctx)
  writer.write_field("id", self.id)
  writer.write_field("name", self.name)
  writer.write_field("score", self.score)
  writer.write_field("active", self.active)
  writer.write_field("tags", self.tags)
  writer.finish()
}

///|
impl BinaryDeserializer for BenchRecord with fn deserialize(ctx) {
  let stored = ctx.read_u8().to_int()
  let reader = if stored == 0 {
    AdtReader::new_v0(bench_record_metadata, ctx)
  } else {
    AdtReader::new(bench_record_metadata, ctx, stored)
  }
  let id : Int32 = reader.read_field("id", None)
  let name : String = reader.read_field("name", None)
  let score : Double = reader.read_field("score", None)
  let active : Bool = reader.read_field("active", None)
  let tags : Array[String] = reader.read_field("tags", Some([]))
  { id, name, score, active, tags, }
}

///|
fn bench_record() -> BenchRecord {
  {
    id: 12345,
    name: "benchmark-record-name",
    score: 0.1234,
    active: true,
    tags: ["alpha", "beta", "gamma", "delta"],
  }
}

///|
/// Wrap a raising closure into a plain one for the bench harness: any
/// DesertFailure is a bug in the library and aborts the benchmark.
fn bench_safe(f : () -> Unit raise DesertFailure) -> () -> Unit {
  fn() {
    let res : Result[Unit, DesertFailure] = Ok(f()) catch { e => Err(e) }

    match res {
      Ok(_) => ()
      Err(msg) => abort("bench failed: \{msg}")
    }
  }
}

///|
test "bench serialize int total=1000000" (it : @bench.T) {
  it.bench(
    bench_safe(fn() raise DesertFailure {
      it.keep(serialize_to_bytes(123456789))
    }),
  )
}

///|
test "bench deserialize int total=1000000" (it : @bench.T) {
  let data = serialize_to_bytes(123456789)
  it.bench(
    bench_safe(fn() raise DesertFailure {
      let back : Int32 = deserialize_exhaustive(data)
      it.keep(back)
    }),
  )
}

///|
test "bench serialize string total=100000" (it : @bench.T) {
  let s = "The quick brown fox jumps over the lazy dog"
  it.bench(
    bench_safe(fn() raise DesertFailure { it.keep(serialize_to_bytes(s)) }),
  )
}

///|
test "bench deserialize string total=100000" (it : @bench.T) {
  let data = serialize_to_bytes("The quick brown fox jumps over the lazy dog")
  it.bench(
    bench_safe(fn() raise DesertFailure {
      let back : String = deserialize_exhaustive(data)
      it.keep(back)
    }),
  )
}

///|
test "bench serialize varint total=1000000" (it : @bench.T) {
  let out = ByteOutput::new()
  let ctx = SerializationContext::new(
    out,
    SerializerState::new(),
    Options::default(),
  )
  it.bench(
    bench_safe(fn() raise DesertFailure {
      it.keep(ctx.write_var_i32(-123456789))
    }),
  )
}

///|
test "bench roundtrip array of ints total=10000" (it : @bench.T) {
  let values : Array[Int32] = []
  for i in 0..<1000 {
    values.push(i)
  }
  it.bench(
    bench_safe(fn() raise DesertFailure {
      let data = serialize_to_bytes(values)
      let back : Array[Int32] = deserialize_exhaustive(data)
      it.keep(back)
    }),
  )
}

///|
test "bench roundtrip byte block total=20000" (it : @bench.T) {
  let payload = Bytes::repeat(b"x", 4096)
  it.bench(
    bench_safe(fn() raise DesertFailure {
      let data = serialize_to_bytes(payload)
      let back : Bytes = deserialize_exhaustive(data)
      it.keep(back)
    }),
  )
}

///|
test "bench roundtrip evolved record total=20000" (it : @bench.T) {
  let record = bench_record()
  it.bench(
    bench_safe(fn() raise DesertFailure {
      let data = serialize_to_bytes(record)
      let back : BenchRecord = deserialize_exhaustive(data)
      it.keep(back)
    }),
  )
}

///|
test "bench string dedup total=20000" (it : @bench.T) {
  let values : Array[DeduplicatedString] = []
  for _i in 0..<100 {
    values.push(DeduplicatedString::new("repeated-deduplicated-string"))
  }
  it.bench(
    bench_safe(fn() raise DesertFailure {
      let data = serialize_to_bytes(values)
      let back : Array[DeduplicatedString] = deserialize_exhaustive(data)
      it.keep(back)
    }),
  )
}

///|
test "bench serialize size estimation total=20000" (it : @bench.T) {
  let record = bench_record()
  it.bench(
    bench_safe(fn() raise DesertFailure { it.keep(serialized_size(record)) }),
  )
}

///|
pub extend BenchRecord with Eq::{not_equal, equal}
