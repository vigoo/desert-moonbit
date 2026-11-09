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
