# Code emission strategy — options considered

The generator's job: turn scanned `#desert(binary_codec)` annotations into
canonical, `moon fmt`-clean MoonBit `impl` blocks. Four approaches were
considered; the repository ships option A with two mandatory quality gates.

## A. String building + parse-back validation + official formatter (current)

Emission builds MoonBit source in a `StringBuilder` from templates; the
result is then **re-parsed with `moonbitlang/parser`** (any syntax error
aborts the run) and **formatted with `moonbitlang/parser/fmt`**, so the
written file is always canonical `moon fmt` style regardless of template
sloppiness.

- Pros: zero extra dependencies beyond the parser; fast; the parse-back gate
  turns "stringly-typed" emission into checked emission (invalid output
  cannot be written); the formatter owns all layout decisions; immune to
  parser AST version churn (only `parse_string` and `impls_to_string` are
  used, both stable entry points).
- Cons: templates are strings — no compiler help if a template produces
  semantically-wrong-but-parseable code (mitigated by the golden tests in
  `codegen_demo` and the unit tests on the emitters); escaping care needed
  for user-provided fragments (default expressions are embedded verbatim —
  intentional, they are expressions).
- Evidence: this is also the approach of the golemcloud/golem MoonBit SDK
  tools (the largest known MoonBit codegen), which likewise builds strings
  and formats with `moonbitlang/parser/fmt`.

## B. Construct `@syntax.Impl` AST nodes, format with `impls_to_string`

- Pros: fully structured emission; invalid constructs are unrepresentable;
  same canonical output via the formatter.
- Cons: the parser's `Impl` struct has ~20 fields (locations, doc strings,
  visibility, quantifiers, error types...) that must all be filled with
  dummy values; the AST types are versioned with the parser (0.x releases
  churn — fields get added/renamed), so the generator would need updates on
  every parser upgrade; significantly more code for identical output.

## C. `moonbit-community/prettyprinter` combinators

- Pros: layout/indentation algebra for structured emission; decoupled from
  the parser's AST; nicer to compose than raw strings for deeply nested
  output.
- Cons: extra dependency for the tool; not MoonBit-syntax-aware (still
  hand-encoding the grammar, just prettier); output still needs the
  parse-back validation; the emission shapes here (flat impl blocks with
  simple nesting) don't stress a pretty-printer's layout algorithm.

## D. Hybrid (strings for stable boilerplate + AST/combinators for volatile parts)

- Pros: best of both where it matters.
- Cons: two systems to maintain; the volatile parts (evolution branches) are
  exactly the ones with the most template variety, so the benefit is small.

## Recommendation

Stay on A. The parse-back + formatter pipeline already provides the safety
that B/C would add, at a fraction of the complexity, and matches the proven
golem SDK approach. Revisit C only if emission grows deeply-nested or
layout-sensitive constructs (e.g. when container-level enum evolution is
implemented, if ever). B is not recommended while `moonbitlang/parser` is
pre-1.0.
