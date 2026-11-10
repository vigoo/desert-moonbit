///|
/// Apples-to-apples comparison harness mirroring the Rust measurement
/// script used for desert-rust (plain timing loops, accumulation into a
/// sum to prevent dead-code elimination — no framework boxing). Run with
/// `moon test bench_compare` on any target; numbers land in the console.

///|
fn cmp_measure(
  name : String,
  iters : Int32,
  f : () -> Int64 raise DesertFailure,
) -> Unit raise DesertFailure {
  let warmup = if iters / 10 < 100 { 100 } else { iters / 10 }
  for _ in 0..<warmup {
    let _ = f()
  }
  let ts = @bench.monotonic_clock_start()
  let mut acc : Int64 = 0L
  for _ in 0..<iters {
    acc = acc + f()
  }
  let elapsed_us = @bench.monotonic_clock_end(ts)
  let ns_per_op = elapsed_us * 1000.0 / iters.to_double()
  if ns_per_op >= 1000.0 {
    println("\{name}  \{ns_per_op / 1000.0} us/op  (\{iters} iters)")
  } else {
    println("\{name}  \{ns_per_op} ns/op  (\{iters} iters)")
  }
  let _ = acc
}

///|
test "comparison harness vs desert-rust" {
  let iters_hi = 1000000
  let iters_md = 100000
  let record = BenchRecord::{
    id: 12345,
    name: "benchmark-record-name",
    score: 0.1234,
    active: true,
    tags: ["alpha", "beta", "gamma", "delta"],
  }

  cmp_measure("baseline (empty op)", iters_hi, fn() { 1L })

  cmp_measure("serialize i32", iters_hi, fn() raise DesertFailure {
    serialize_to_bytes(123456789).length().to_int64()
  })

  let int_data = serialize_to_bytes(123456789)
  cmp_measure("deserialize i32", iters_hi, fn() raise DesertFailure {
    let back : Int32 = deserialize_exhaustive(int_data)
    back.to_int64()
  })

  let s = "The quick brown fox jumps over the lazy dog"
  cmp_measure("serialize string (43B)", iters_md, fn() raise DesertFailure {
    serialize_to_bytes(s).length().to_int64()
  })

  let string_data = serialize_to_bytes(s)
  cmp_measure("deserialize string (43B)", iters_md, fn() raise DesertFailure {
    let back : String = deserialize_exhaustive(string_data)
    back.length().to_int64()
  })

  cmp_measure("write var_i32(-123456789)", iters_hi, fn() raise DesertFailure {
    let out = ByteOutput::new(capacity=16)
    let ctx = SerializationContext::new(
      out,
      SerializerState::new(),
      Options::default(),
    )
    ctx.write_var_i32(-123456789)
    out.length().to_int64()
  })

  let values : Array[Int32] = []
  for i in 0..<1000 {
    values.push(i)
  }
  cmp_measure("roundtrip Array<Int> x1000", 10000, fn() raise DesertFailure {
    let data = serialize_to_bytes(values)
    let back : Array[Int32] = deserialize_exhaustive(data)
    back.length().to_int64()
  })

  let payload = Bytes::repeat(b"x", 4096)
  cmp_measure("roundtrip Bytes 4096B", 20000, fn() raise DesertFailure {
    let data = serialize_to_bytes(payload)
    let back : Bytes = deserialize_exhaustive(data)
    back.length().to_int64()
  })

  cmp_measure("roundtrip evolved record", 20000, fn() raise DesertFailure {
    let data = serialize_to_bytes(record)
    let back : BenchRecord = deserialize_exhaustive(data)
    back.id.to_int64()
  })

  let dedup_values : Array[DeduplicatedString] = []
  for _i in 0..<100 {
    dedup_values.push(DeduplicatedString::new("repeated-deduplicated-string"))
  }
  cmp_measure("dedup strings x100", 20000, fn() raise DesertFailure {
    let data = serialize_to_bytes(dedup_values)
    let back : Array[DeduplicatedString] = deserialize_exhaustive(data)
    back.length().to_int64()
  })

  cmp_measure("serialized_size(record)", 20000, fn() raise DesertFailure {
    serialized_size(record).to_int64()
  })
}

///|
/// Gap-case measurements (added to cover the optimization roadmap):
/// buffer reuse, string-heavy collections, maps, options, compression,
/// evolution reader paths, dedup reads, scaling points, and the golden
/// dataset as a real-life complex workload.

///|
test "comparison harness part 2 (gap cases)" {
  let iters_md = 100000

  // Buffer-reuse pattern: reset + write into a caller-owned output
  // (mirrors desert-rust's serialize_into_byte_vec).
  let out = ByteOutput::new(capacity=256)
  let reuse_ctx = SerializationContext::new(
    out,
    SerializerState::new(),
    Options::default(),
  )
  cmp_measure("serialize i32 (reused buffer)", iters_md, fn() raise DesertFailure {
    out.reset()
    reuse_ctx.write_i32(123456789)
    out.length().to_int64()
  })

  // String-heavy collection: per-element transcode.
  let strings : Array[String] = []
  for i in 0..<100 {
    strings.push("name-\{i}-padding")
  }
  cmp_measure("roundtrip Array<String> x100", 20000, fn() raise DesertFailure {
    let data = serialize_to_bytes(strings)
    let back : Array[String] = deserialize_exhaustive(data)
    back.length().to_int64()
  })

  // Map codec with per-entry 2-tuple framing.
  let map : Map[String, Int32] = Map([], capacity=256)
  for i in 0..<100 {
    map.set("key-\{i}", i)
  }
  cmp_measure("roundtrip Map<String,Int> x100", 10000, fn() raise DesertFailure {
    let data = serialize_to_bytes(map)
    let back : Map[String, Int32] = deserialize_exhaustive(data)
    back.length().to_int64()
  })

  // Option wrapper: tag + payload.
  let opt : Int32? = Some(12345)
  cmp_measure("roundtrip Option<Int>", 1000000, fn() raise DesertFailure {
    let data = serialize_to_bytes(opt)
    let back : Int32? = deserialize_exhaustive(data)
    match back {
      Some(v) => v.to_int64()
      None => 0L
    }
  })

  // Compressed byte block: DEFLATE compress + decompress per op.
  let payload = Bytes::repeat(b"x", 4096)
  cmp_measure("roundtrip compressed 4096B", 2000, fn() raise DesertFailure {
    let compressed = compress_bytes(payload)
    let back = decompress_bytes(compressed)
    back.length().to_int64()
  })

  // Evolution: old version-0 data read by a newer reader, extra field
  // falling back to its FieldAdded default.
  let old_data : Bytes = b"\x00\x00\x00\x00\x2a"
  cmp_measure("deserialize V0 data w/ defaults", 1000000, fn() raise DesertFailure {
    let back : WithExtra = deserialize_exhaustive(old_data)
    back.base.to_int64()
  })

  // Evolution: V2 multi-chunk record (header w/ FieldRemoved + dedup
  // string, two generation chunks) roundtrip — the byte-exact Point
  // example.
  let point = Point::{ x: 1, y: -10, cached_str: None, }
  cmp_measure("roundtrip V2 multi-chunk record", 200000, fn() raise DesertFailure {
    let data = serialize_to_bytes(point)
    let back : Point = deserialize_exhaustive(data)
    back.x.to_int64()
  })

  // Deserialize-side dedup: table-hit heavy back-reference reads.
  let dedup_values : Array[DeduplicatedString] = []
  for _i in 0..<100 {
    dedup_values.push(DeduplicatedString::new("repeated-deduplicated-string"))
  }
  let dedup_data = serialize_to_bytes(dedup_values)
  cmp_measure("deserialize dedup backrefs x100", 50000, fn() raise DesertFailure {
    let back : Array[DeduplicatedString] = deserialize_exhaustive(dedup_data)
    back.length().to_int64()
  })

  // Scaling point: 10x the array case.
  let big_values : Array[Int32] = []
  for i in 0..<10000 {
    big_values.push(i)
  }
  cmp_measure("roundtrip Array<Int> x10000", 5000, fn() raise DesertFailure {
    let data = serialize_to_bytes(big_values)
    let back : Array[Int32] = deserialize_exhaustive(data)
    back.length().to_int64()
  })

  // Scaling point: 64 KB byte block.
  let big_block = Bytes::repeat(b"x", 65536)
  cmp_measure("roundtrip Bytes 64KB", 2000, fn() raise DesertFailure {
    let data = serialize_to_bytes(big_block)
    let back : Bytes = deserialize_exhaustive(data)
    back.length().to_int64()
  })

  // Golden dataset: the 242,540-byte dataset written by desert-scala —
  // a real-life complex model (nested exceptions with 16-frame stack
  // traces, evolved record, sorted-constructor enum with a transient
  // case, dedup strings, collections).
  let dataset = golden_dataset1()
  let golden_model : GoldenModel = deser_evolved(dataset)
  if golden_model.string != "Example data set" {
    abort("golden setup mismatch")
  }
  cmp_measure("golden dataset serialize", 2000, fn() {
    ser_evolved(golden_model).length().to_int64()
  })
  cmp_measure("golden dataset deserialize", 2000, fn() {
    let back : GoldenModel = deser_evolved(dataset)
    back.string.length().to_int64()
  })
}

///|
test "comparison harness part 3 (context reuse for deserialization)" {
  // Deser-side counterpart of the reused-buffer canary: reset a
  // deserialization context instead of allocating per op.
  let int_data = serialize_to_bytes(123456789)
  let ctx = DeserializationContext::new(
    BinaryInput::new(int_data),
    SerializerState::new(),
    Options::default(),
  )
  cmp_measure("deserialize i32 (reused ctx)", 1000000, fn() raise DesertFailure {
    ctx.reset_input(int_data)
    let back : Int32 = BinaryDeserializer::deserialize(ctx)
    back.to_int64()
  })

  let record = BenchRecord::{
    id: 12345,
    name: "benchmark-record-name",
    score: 0.1234,
    active: true,
    tags: ["alpha", "beta", "gamma", "delta"],
  }
  let record_data = serialize_to_bytes(record)
  let rctx = DeserializationContext::new(
    BinaryInput::new(record_data),
    SerializerState::new(),
    Options::default(),
  )
  cmp_measure("deserialize record (reused ctx)", 200000, fn() raise DesertFailure {
    rctx.reset_input(record_data)
    let back : BenchRecord = BinaryDeserializer::deserialize(rctx)
    back.id.to_int64()
  })
}
