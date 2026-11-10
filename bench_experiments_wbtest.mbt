///|
/// Cost-decomposition experiments for the comparison report: isolates
/// where the per-op time goes on small payloads (allocation vs trait
/// dispatch vs format work vs Bytes copy).

///|
fn exp_measure(
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
  let ns = elapsed_us * 1000.0 / iters.to_double()
  println("EXP \{name}  \{ns} ns/op")
  let _ = acc
}

///|
test "decompose serialize i32 costs" {
  let iters = 1000000

  // A. The full public path (what the comparison harness measured).
  exp_measure("A full serialize_to_bytes", iters, fn() raise DesertFailure {
    serialize_to_bytes(123456789).length().to_int64()
  })

  // B. Reused output + reused context: only format work + buffer growth.
  let out = ByteOutput::new(capacity=64)
  let ctx = SerializationContext::new(
    out,
    SerializerState::new(),
    Options::default(),
  )
  exp_measure("B reused ctx: write_i32", iters, fn() raise DesertFailure {
    out.reset()
    ctx.write_i32(123456789)
    out.length().to_int64()
  })

  // C. Direct Buffer writes: isolates trait dispatch through the context.
  exp_measure("C direct Buffer.write_int_be", iters, fn() {
    out.reset()
    out.buffer.write_int_be(123456789)
    out.length().to_int64()
  })

  // D. Allocation cost alone: fresh output + state + context, no work.
  exp_measure("D alloc output+state+ctx only", iters, fn() {
    let fresh = ByteOutput::new(capacity=64)
    let _ = SerializationContext::new(
      fresh,
      SerializerState::new(),
      Options::default(),
    )
    fresh.length().to_int64()
  })

  // E. State allocation alone (should be near zero after the lazy fix).
  exp_measure("E SerializerState::new only", iters, fn() {
    let _ = SerializerState::new()
    0L
  })

  // F. Bytes copy cost: write once, then to_bytes() per op.
  out.reset()
  ctx.write_i32(123456789)
  exp_measure("F reused ctx + to_bytes copy", iters, fn() raise DesertFailure {
    out.reset()
    ctx.write_i32(123456789)
    out.to_bytes().length().to_int64()
  })

  // G. Deserialize decomposition: full path.
  let data = serialize_to_bytes(123456789)
  exp_measure("G full deserialize_exhaustive", iters, fn() raise DesertFailure {
    let back : Int32 = deserialize_exhaustive(data)
    back.to_int64()
  })

  // H. Reused input: only the cursor read.
  let input = BinaryInput::new(data)
  let rctx = DeserializationContext::new(
    input,
    SerializerState::new(),
    Options::default(),
  )
  exp_measure("H reused input: read_i32", iters, fn() raise DesertFailure {
    rctx.input.seek(0)
    rctx.input.read_i32().to_int64()
  })
}
