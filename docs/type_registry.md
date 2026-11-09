# Type registry

The type registry serializes values whose concrete type is not known at
compile time — the escape hatch that powers actor-framework style
serialization (desert-akka/desert-pekko in Scala, `serializeUnknown`).

> Note: desert-rust does not implement the registry yet; this subsystem
> follows the Scala original.

## Registering types

```mbt
let registry = @desert.TypeRegistryBuilder::new()
  .register("myapp.UserCreated", ctx => {
    let v : UserCreated = @desert.BinaryDeserializer::deserialize(ctx)
    v as &@desert.RegisteredValue
  })
  .register_placeholder()
  .register("myapp.UserRenamed", ctx => {
    let v : UserRenamed = @desert.BinaryDeserializer::deserialize(ctx)
    v as &@desert.RegisteredValue
  })
  .freeze()
```

- Ids are consecutive integers starting from 1, in registration order.
- `register_placeholder` reserves an id without a type — use it to retire a
  type while keeping every other id stable on the wire.
- Registration fails on duplicate type names.
- `TypeRegistry::empty()` fails all lookups.

Types participating in the registry implement the `RegisteredValue` trait
(`registered_type_name` + `serialize_registered`). `#desert(binary_codec,
type_id = "myapp.UserCreated")` generates these implementations
automatically from the code generator.

## Wire format

`write_unknown` writes `var_u32(type_id)` followed by the registered codec's
payload inline — no markers, no length prefix (byte-compatible with the
Scala library). `read_unknown` reads the id, looks the entry up and runs its
typed constructor, returning a `RegisteredBox` with the resolved id, type
name and erased value.

Unknown ids and unregistered types are hard failures (`InvalidTypeId`,
`TypeNotRegistered`): there is no way to skip an unknown payload because the
format carries no length information for it. Version your registry
explicitly (placeholders) when payloads change shape.

Because MoonBit has no runtime downcast, extract the concrete value by
matching on `type_name` and re-serializing the erased value through a
concrete codec, or model open sets as an enum of your known cases and
register the enum.

The string-deduplication state is shared between the id prefix, payloads and
subsequent values, matching the Scala behavior.
