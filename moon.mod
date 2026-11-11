// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "vigoo/desert"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/vigoo/desert-moonbit"

license = "Apache-2.0"

keywords = [ "serialization", "binary", "codec", "evolution", "moonbit" ]

preferred_target = "wasm-gc"

supported_targets = "+wasm+wasm-gc+js+native"

description = "Binary serialization with schema evolution, wire-compatible with desert (Scala) and desert-rust"
