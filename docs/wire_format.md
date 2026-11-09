# Wire format reference

Global properties: no magic header, no framing, no checksum. All fixed-width
integers and floats are **big-endian**. Varints are LEB128-style base-128
(least-significant 7 bits first, high bit = continuation, 1–5 bytes for
32-bit values). `var_i32` zigzag-maps the value first; `var_u32` writes it
raw.

```
var_u32 examples: 0→00 | 127→7f | 128→80 01 | 16383→ff 7f
var_i32 examples: 10→14 | -1→01 | -64→7f | -2→03
```

## Primitives

```
Byte        : 1 byte
Bool        : 01 | 00
UInt16      : 2 BE
Int/UInt    : 4 BE
Int64/UInt64: 8 BE
Float       : 4 BE IEEE-754 bits
Double      : 8 BE IEEE-754 bits
Unit        : (nothing)
Char        : var_u32(code point)          e.g. 'A'→41, 'λ'→bb 07
Char (scala): u16 BE UTF-16 unit           e.g. 'A'→00 41
String      : var_i32(nbytes) utf8         e.g. "hello"→0a 68 65 6c 6c 6f
DedupString : new→ as String; repeat→ var_i32(-id)  (ids from 1)
Bytes       : var_u32(len) ++ raw          e.g. 4 bytes→04 01 02 03 04
```

## Wrappers

```
Option<T>   : 01 ++ T | 00
Result<R,E> : 01 ++ R | 00 ++ E
Tuple n>=2  : 00 ++ T1 ++ ... ++ Tn        (version-0 record)
```

## Collections

```
counted      : var_i32(count) ++ count elements
unknown size : var_i32(-1) ++ (01 ++ elem)* ++ 00
Map entries  : each pair as a 2-tuple (00 ++ K ++ V)
fixed byte   : var_u32(len) ++ raw bytes
compressed   : var_u32(uncompressed) var_u32(compressed) deflate(bytes)
```

## Records

```
version 0      : 00 ++ fields in declaration order     (== tuple of arity n)
version V>0    : u8(V) ++ (V+1) header entries ++ chunks in version order
header entry   : FieldAdded  → var_i32(chunk size)
                 MadeOptional→ var_i32(-1) ++ FieldPosition byte
                 Removed     → var_i32(-2) ++ DeduplicatedString(name)
                 unknown     → var_i32(0)
FieldPosition  : chunk==0 → -(position) as i8 ; chunk>0 → chunk
```

## Enums

```
enum           : u8(enum version) ++ var_u32(constructor idx) ++ case payload
case payload   : unit-transparent → nothing
                 otherwise → u8(case version) ++ fields
                 (case with evolution steps: header + chunks as above)
constructor ids: 0-based, skipping transient cases
                 (sorted_constructors: lexical order)
```

## Verified samples (produced by both original implementations)

```
i32 42                → 00 00 00 2a
Some(7i32)            → 01 00 00 00 07          None::<i32> → 00
vec![1i32,2,3]        → 06 00 00 00 01 00 00 00 02 00 00 00 03
vec![1u8,2,3,4]       → 04 01 02 03 04
(42i32, true)         → 00 00 00 00 2a 01
HashMap{"a"→1i32}     → 02 00 02 61 00 00 00 01
Dedup("same","same","","")
                      → 08 73 61 6d 65 01 00 03
struct{a:i32=1,b:"x"} → 00 00 00 00 01 02 78    (identical to (i32,String))
evolved Point         → 02 08 08 03 02 7a ff ff ff f6 00 00 00 01
```
