# desert-codegen

Code generator for [vigoo/desert](https://mooncakes.io/docs/vigoo/desert):
derives `BinarySerializer` / `BinaryDeserializer` implementations for
MoonBit structs and enums annotated with `#desert(binary_codec)`.

## Usage

From a clone of the [desert-moonbit repository](https://github.com/vigoo/desert-moonbit)
(a MoonBit workspace containing this tool):

```sh
moon run codegen -- <absolute path to your package directory>
```

The generator scans `*.mbt` files in the given package, finds annotated
types, and writes a `desert_derive.mbt` file next to them with the codec
implementations (formatted with the official MoonBit formatter). It also
adds the `vigoo/desert` import to the package's `moon.pkg` if missing.
Re-run it after changing annotated types; the output is deterministic and
idempotent.

See the main library docs for the full annotation reference:
[docs/getting_started.md](../docs/getting_started.md).

## Supported annotations

- `#desert(binary_codec)` — derive a codec for a struct or enum
- `evolution(FieldAdded("f", default), FieldMadeOptional("f"), FieldRemoved("f"), FieldMadeTransient("f"))` — schema history for structs and individual enum cases
- `type_id = "pkg.TypeName"` — also derive `RegisteredValue` for the type registry
- `sorted_constructors` (enums) — assign constructor ids in lexical order
- `transparent` (single-field structs/cases) — encode the inner value directly
- `#transient(expr)` on fields — skip on wire, use `expr` when reading
- `#desert(transient)` on enum cases — the case cannot be serialized and consumes no constructor id

Not supported: container-level evolution on enums (put steps on cases),
`custom` wrappers, tuple structs.

## Development

```sh
moon check        # type check
moon test         # unit tests for the parser/emitter pipeline
moon fmt
```
