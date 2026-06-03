# Mutator Specification

This document defines the mutation operators zentinel may generate. A mutator is stable only when this document defines its transformation, allowed contexts, forbidden contexts, equivalent-mutant risks, fixture requirements, and compile-error expectations.

The AST backend is the stable implementation target. ZIR and AIR backends may implement compatible operators later, but they must emit the same shared mutant model and result semantics.

## Common Rules

All mutators must:

- preserve syntactically valid Zig unless the operator explicitly allows compile-error mutants
- emit exact source spans
- produce deterministic mutant IDs
- avoid mutating code inside `test` declarations by default
- avoid mutating generated files unless explicitly included
- include a stable operator name in reports
- include `expected_compile` as `compiles`, `may_fail`, or `must_fail`

All mutators must not:

- use AI output to decide whether a candidate is valid
- silently discard candidates because they might be equivalent
- mutate comments or string contents
- mutate code outside configured include roots
- mutate a file more than once for a single mutant

## Operator Stability

| Stability | Meaning |
| --- | --- |
| stable | Wired into the run and `list-mutants` generators; enabled by default when the containing phase is complete and may be listed in `[mutators] enabled`. |
| preview | Documented design target with no collector wired into the pipeline. It is **rejected** if listed in `[mutators] enabled` (it would otherwise emit zero mutants) until a later task promotes it to stable. |
| experimental | Backend or semantics are not stable; never enabled by default. |

Preview operators are documented design targets, not minimum-product implementation tasks. End-to-end completion excludes preview mutator implementation. A stable task may add fixtures that protect a preview operator's future contract, but it must not implement or enable a preview operator unless the task title or acceptance criteria names that operator explicitly.

Every operator that loads successfully in `[mutators] enabled` is wired into both generators and emits mutants on code containing its target construct; config rejects any name that is unknown or `preview`. The stable operators in the catalog below are exactly the operators the pipeline can emit.

For config expansion, `phase2` means stable Phase 2 operators only. Preview Phase 2 entries in the catalog are design targets and do not become enabled through `phase2` or `all_stable` until a later task promotes them to stable.

## Operator Catalog

| Operator | Phase | Stability | Summary |
| --- | --- | --- | --- |
| `arithmetic_add_sub` | 1 | stable | `+` to `-`, `-` to `+`. |
| `arithmetic_mul_div` | 1 | stable | `*` to `/`, `/` to `*`. |
| `equality_swap` | 1 | stable | `==` to `!=`, `!=` to `==`. |
| `comparison_boundary` | 1 | stable | Inclusive/exclusive boundary swap. |
| `logical_and_or` | 1 | stable | `and` to `or`, `or` to `and`. |
| `boolean_literal` | 1 | stable | `true` to `false`, `false` to `true`. |
| `optional_orelse_unreachable` | 2 | stable | Replace fallback with `unreachable`. |
| `optional_orelse_default` | 2 | preview | Replace fallback expression with type default when safe. |
| `optional_null_check` | 2 | stable | Swap `x == null` and `x != null`. |
| `error_catch_unreachable` | 2 | stable | Replace `catch` handler with `unreachable`. |
| `error_catch_return` | 2 | preview | Replace handler with propagated return when type-compatible. |
| `try_to_catch_unreachable` | 2 | preview | Replace `try expr` with `expr catch unreachable`. |
| `defer_remove` | 2 | preview | Remove `defer` body by replacing with empty block. |
| `errdefer_remove` | 2 | stable | Remove `errdefer` body by replacing with empty block. |
| `allocator_failure_path` | 2 | preview | Force allocation failure branch in fixture-controlled contexts. |
| `comptime_branch_flip` | 2 | preview | Flip compile-time boolean branch. |
| `comptime_value_boundary` | 2 | preview | Mutate integer comptime constants by `+1` or `-1`. |
| `safety_unreachable_to_return` | 2 | preview | Replace selected `unreachable` with configured return/panic equivalent. |
| `integer_literal_boundary` | 2 | stable | Mutate integer literals used as bounds by `+1` or `-1`. |
| `loop_boundary` | 2 | stable | Mutate loop range bounds and while comparisons. |

## Phase 1 Stable Operators

### `arithmetic_add_sub`

| Field | Contract |
| --- | --- |
| Before | `a + b`, `a - b` |
| After | `a - b`, `a + b` |
| Allowed contexts | Binary arithmetic expressions for integer, float, vector, or comptime numeric operands. |
| Forbidden contexts | Pointer arithmetic not represented as normal Zig binary numeric expression; unary `-x`; wrapping operators such as `+%`; saturating operators; compound assignment (`+=`, `-=`) is out of scope for v1 and not mutated; string concatenation-like library calls. |
| Equivalent risks | `a + 0`, `a - 0`, symmetric test data where `b == 0`, unsigned underflow causing compile/runtime failure in some modes. |
| Compile expectation | `may_fail` for unsigned and comptime-known negative results; otherwise `compiles`. |
| Fixture requirements | Include killed and survived examples; include unsigned underflow compile-error or runtime-trap example; include same-file test exclusion. |

Transformations:

```diff
- return lhs + rhs;
+ return lhs - rhs;
```

```diff
- return lhs - rhs;
+ return lhs + rhs;
```

Executable contract:

```zig before
fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

```zig after
fn add(a: i32, b: i32) i32 {
    return a - b;
}
```

### `arithmetic_mul_div`

| Field | Contract |
| --- | --- |
| Before | `a * b`, `a / b` |
| After | `a / b`, `a * b` |
| Allowed contexts | Binary numeric expressions where Zig syntax uses `*` or `/`. |
| Forbidden contexts | Pointer dereference; wrapping/saturating multiplication; division forms requiring explicit builtins; known divisor zero literals; compound assignment (`*=`, `/=`) is out of scope for v1 and not mutated. |
| Equivalent risks | `a * 1`, `a / 1`, fixtures where operands are `0` or `1`. |
| Compile expectation | `may_fail` when replacement creates invalid integer division, division by zero, or comptime-known invalid arithmetic. |
| Fixture requirements | Include integer and float examples; include division-by-zero rejection or compile-error classification. |

### `equality_swap`

| Field | Contract |
| --- | --- |
| Before | `a == b`, `a != b` |
| After | `a != b`, `a == b` |
| Allowed contexts | Equality comparison expressions for values Zig permits to compare. |
| Forbidden contexts | Token sequences inside comments/strings; custom comparison helper calls; comparisons already inside generated test code; comparisons where one operand is the `null` literal (owned by `optional_null_check`). |
| Equivalent risks | Values known to differ in all tests; dead branches; comparisons guarded by identical previous checks. |
| Compile expectation | `compiles`. |
| Fixture requirements | Include boolean, enum, optional, and integer equality examples. |

### `comparison_boundary`

| Field | Contract |
| --- | --- |
| Before | `>=`, `>`, `<=`, `<` |
| After | `>`, `>=`, `<`, `<=` |
| Allowed contexts | Ordered comparisons for integers, floats, enums where ordered comparison is valid, and comptime-known ordered values. |
| Forbidden contexts | Chained comparisons represented as separate AST nodes are mutated one node at a time; comparisons in test declarations by default. |
| Equivalent risks | Missing exact-boundary inputs; floating-point NaN behavior; values constrained away from boundary. |
| Compile expectation | `compiles`. |
| Fixture requirements | Include upper bound, lower bound, array index, and float examples. |

Transformations:

```text
a >= b -> a > b
a > b  -> a >= b
a <= b -> a < b
a < b  -> a <= b
```

Executable contract:

```zig before
fn lt(a: i32, b: i32) bool {
    return a < b;
}
```

```zig after
fn lt(a: i32, b: i32) bool {
    return a <= b;
}
```

### `logical_and_or`

| Field | Contract |
| --- | --- |
| Before | `a and b`, `a or b` |
| After | `a or b`, `a and b` |
| Allowed contexts | Boolean `and`/`or` keyword operations with short-circuit semantics. |
| Forbidden contexts | Bitwise `&` and `\|`; non-boolean operands; code inside tests by default. |
| Equivalent risks | One operand constant; guards where later code makes branches equivalent; tests not covering short-circuit side effects. |
| Compile expectation | `compiles`. |
| Fixture requirements | Include short-circuit side-effect fixture and pure boolean fixture. |

### `boolean_literal`

| Field | Contract |
| --- | --- |
| Before | `true`, `false` |
| After | `false`, `true` |
| Allowed contexts | Boolean literal expressions in production source. |
| Forbidden contexts | Literals in tests by default; config examples; comments; strings; field names. |
| Equivalent risks | Literal used in dead code; literal overwritten before observation. |
| Compile expectation | `compiles`. |
| Fixture requirements | Include return literal, branch condition literal, and struct field default literal. |

Executable contract:

```zig before
fn flag() bool {
    return true;
}
```

```zig after
fn flag() bool {
    return false;
}
```

## Phase 2 Zig-Native Operators

### `optional_orelse_unreachable`

| Field | Contract |
| --- | --- |
| Before | `optional orelse fallback` |
| After | `optional orelse unreachable` |
| Allowed contexts | `orelse` expressions where replacement type-checks or failure is meaningful. |
| Forbidden contexts | Existing `orelse unreachable`; test declarations by default. |
| Equivalent risks | Tests never pass null; fallback is already unreachable through invariants. |
| Compile expectation | `compiles` when `unreachable` coerces; otherwise `may_fail`. |
| Fixture requirements | Include null-covered and null-missing tests. |

### `optional_orelse_default`

| Field | Contract |
| --- | --- |
| Before | `optional orelse fallback` |
| After | `optional orelse default_value` |
| Allowed contexts | Types with deterministic defaults configured by mutator: `false`, `0`, `null`, empty slice literal when syntactically valid. |
| Forbidden contexts | Struct/union values without an explicit configured default; allocations; side-effectful fallback where removing side effects would change more than value semantics. |
| Equivalent risks | Fallback already equals default; null branch untested. |
| Compile expectation | `may_fail` until type inference is proven for the expression. |
| Fixture requirements | Include bool, integer, optional, and rejected struct examples. |

### `optional_null_check`

| Field | Contract |
| --- | --- |
| Before | `x == null`, `x != null`, `null == x`, `null != x` |
| After | Opposite equality comparison. |
| Allowed contexts | Optional comparisons with `null`. |
| Forbidden contexts | Non-optional values that parse syntactically but do not type-check; tests by default. |
| Equivalent risks | Branch not reached; optional always null/non-null by construction. |
| Compile expectation | `compiles` for valid Zig optional comparison; invalid candidates are filtered or classified `compile_error`. |
| Fixture requirements | Include both operand orders. |

### `error_catch_unreachable`

| Field | Contract |
| --- | --- |
| Before | `expr catch handler` |
| After | `expr catch unreachable` |
| Allowed contexts | Error union catch expressions. |
| Forbidden contexts | Existing `catch unreachable`; catch handlers whose side effects are the only intended mutation target for another operator. |
| Equivalent risks | Error path never exercised; handler already terminates. |
| Compile expectation | `may_fail`. Removing the catch handler can leave a captured resource (used only by that handler) unused, which Zig rejects, so a `compile_error` result is an expected outcome here, not a tool defect (M1). |
| Fixture requirements | Include caught error path, success path, and handler side-effect example. |

### `error_catch_return`

| Field | Contract |
| --- | --- |
| Before | `expr catch handler` |
| After | `expr catch return err` or configured error return expression. |
| Allowed contexts | Catch payload is bound and enclosing function returns a compatible error union. |
| Forbidden contexts | No accessible error payload; incompatible return type; top-level comptime blocks without return. |
| Equivalent risks | Handler already returns same error; error path untested. |
| Compile expectation | `may_fail` until semantic analysis can prove compatibility. |
| Fixture requirements | Include compatible and incompatible return type examples. |

### `try_to_catch_unreachable`

| Field | Contract |
| --- | --- |
| Before | `try expr` |
| After | `expr catch unreachable` |
| Allowed contexts | `try` over error unions. |
| Forbidden contexts | Tests by default; syntax where removing `try` changes precedence unless parentheses are inserted exactly. |
| Equivalent risks | Error path impossible in tests; caller already treats panic as failure. |
| Compile expectation | `compiles` when precedence is preserved. |
| Fixture requirements | Include nested calls and parenthesized expressions. |

### `defer_remove`

| Field | Contract |
| --- | --- |
| Before | `defer statement;` or `defer { statements }` |
| After | `defer {}` |
| Allowed contexts | Defer statements in production functions. |
| Forbidden contexts | Defer containing compile-time declarations; tests by default; statements where empty block is syntactically invalid in the backend representation. |
| Equivalent risks | Cleanup irrelevant for tested path; allocator/test harness catches cleanup independently. |
| Compile expectation | `may_fail` for declaration-heavy or scope-sensitive statements. |
| Fixture requirements | Include resource cleanup and harmless defer examples. |

### `errdefer_remove`

| Field | Contract |
| --- | --- |
| Before | `errdefer statement;` or `errdefer { statements }` |
| After | `errdefer {}` |
| Allowed contexts | Error cleanup paths. |
| Forbidden contexts | Tests by default; declaration-only bodies. |
| Equivalent risks | Error path untested; cleanup not observable. |
| Compile expectation | `may_fail` for scope-sensitive statements. |
| Fixture requirements | Include allocator cleanup on error and success-only path. |

### `allocator_failure_path`

| Field | Contract |
| --- | --- |
| Before | Allocation success path using configured allocator call. |
| After | Deterministic fixture-controlled failure branch or injected failing allocator wrapper. |
| Allowed contexts | Fixture projects and target modules that operate on explicitly injected allocator wrappers owned by the sandboxed target command. |
| Forbidden contexts | Arbitrary source rewrites that guess allocator semantics; zentinel runner allocator paths; harness allocator paths; global allocator setup; production default until stable wrapper sandbox support exists. |
| Equivalent risks | Tests do not assert error cleanup; allocation not reached. |
| Compile expectation | `may_fail` until harness support exists; stable form must compile. |
| Fixture requirements | Include failing allocator fixture, leak-detection fixture, and a guard proving the mutator cannot reach the runner or harness allocator. |

### `comptime_branch_flip`

| Field | Contract |
| --- | --- |
| Before | `if (comptime_bool) a else b` or equivalent compile-time condition. |
| After | Boolean condition negated or branches swapped with identical source mapping semantics. |
| Allowed contexts | Conditions known to be compile-time booleans through syntax or backend metadata. |
| Forbidden contexts | Runtime conditions; generic code where source mapping cannot isolate branch. |
| Equivalent risks | Both branches produce same result; inactive branch does not compile. |
| Compile expectation | `may_fail`, because inactive compile-time branches may contain invalid code for the target. |
| Fixture requirements | Include compiling inactive branch and intentionally non-compiling inactive branch. |

### `comptime_value_boundary`

| Field | Contract |
| --- | --- |
| Before | Comptime integer constant used in array length, loop bound, or type-level calculation. |
| After | Constant `+1` or `-1` according to deterministic candidate order. |
| Allowed contexts | Integer literals or named comptime constants with local source span. |
| Forbidden contexts | Extern ABI values; bit widths; alignment values unless explicitly enabled; public protocol constants by default. |
| Equivalent risks | Constant not covered by tests; generated shape still valid. |
| Compile expectation | `may_fail` for invalid array lengths, invalid bit widths, or type mismatches. |
| Fixture requirements | Include array length, loop bound, and rejected ABI constant examples. |

### `safety_unreachable_to_return`

| Field | Contract |
| --- | --- |
| Before | `unreachable` |
| After | Configured replacement such as `return error.Unexpected` or `@panic("zentinel mutant")` when type-compatible. |
| Allowed contexts | Functions with configured replacement strategy and type compatibility. |
| Forbidden contexts | Bare expressions where replacement cannot type-check; existing panic calls; tests by default. |
| Equivalent risks | Path unreachable in all tests; replacement still terminates. |
| Compile expectation | `may_fail` unless type compatibility is proven. |
| Fixture requirements | Include Debug vs ReleaseFast safety-mode behavior. |

### `integer_literal_boundary`

| Field | Contract |
| --- | --- |
| Before | Integer literal used in a branch, range, slice, or length check. |
| After | Literal incremented or decremented by one. |
| Allowed contexts | Literals in runtime or comptime expressions where local mutation is meaningful. |
| Forbidden contexts | Version numbers; error codes; enum tags; ABI constants; bit widths; alignments by default. |
| Equivalent risks | Boundary values untested; literal is not semantically a boundary. |
| Compile expectation | `may_fail` for type range overflow. |
| Fixture requirements | Include `0`, `1`, max-like constants, and rejected alignment examples. |

### `loop_boundary`

| Field | Contract |
| --- | --- |
| Before | `while (i < n)`, `while (i <= n)`, ranges `a..b`. |
| After | Comparison boundary swap or range end `+1`/`-1` where syntactically safe. |
| Allowed contexts | Loop termination checks and range expressions. |
| Forbidden contexts | Infinite loops without static guard; ranges over non-integer values; tests by default. |
| Equivalent risks | Empty loops; tests only cover zero iterations; sentinel values. |
| Compile expectation | `may_fail` for invalid ranges or type overflow. |
| Fixture requirements | Include zero, one, many, and exact-end iteration tests. |

## Candidate Ordering

Candidates are sorted by:

1. project-relative file path
2. byte start offset
3. byte end offset
4. operator name
5. replacement text
6. backend name

Parallel execution must not change this order.

## Operator Overlap and Precedence

When more than one operator could match the same source span, exactly one candidate survives, so candidate counts and durable IDs stay reproducible. Two mechanisms enforce this:

- **Context ownership.** An operator may decline a context another operator owns, so the duplicate is never collected. Documented ownership rules:
  - `null` equality comparisons (`x == null`, `x != null`, and the reversed `null == x` / `null != x` operand orders) are owned by `optional_null_check`; `equality_swap` does not emit candidates for them.
- **Physical-edit deduplication (`sortAndDedupe`, src/mutant.zig).** When two operators nonetheless collect candidates for the same physical edit — an identical `(file, span, original, replacement)` tuple — exactly one is retained: the first in canonical Candidate Ordering. Because that order's operator key (sort key 4) is alphabetical, the alphabetically earlier operator name wins (e.g. `comparison_boundary` is kept over `loop_boundary`). This makes same-edit overlaps deterministic with no explicit rule, so adding an operator can never inflate counts with a duplicate edit. Documented same-edit overlaps resolved this way:
  - A boundary comparison (`<`, `<=`, `>`, `>=`) in a `while` loop condition is recognized by **both** `comparison_boundary` (it matches every comparison node) and `loop_boundary` (its `whileCond` walks the condition); they emit the identical physical edit. Deduplication keeps the `comparison_boundary` representative, so `comparison_boundary` owns the while-condition boundary swap in the canonical candidate set and `loop_boundary` contributes no separate candidate there. (Pinned by `test/ast_candidate_ordering_test.zig`: a real `while (i < n)` yields exactly one candidate, `comparison_boundary`, `<` → `<=`.)

Physical-edit deduplication is the authoritative backstop; an operator MAY additionally restrict its contexts to avoid a redundant collection, but is not required to. The two mechanisms are distinct: context ownership decides which candidate is *collected*, while deduplication decides which of several already-collected same-edit candidates is *retained* (the alphabetically earlier operator name).

## Compile-Error Classification

Compile errors are valid deterministic outcomes. A compile-error mutant is:

- `compile_error` when the patched source fails to compile before tests execute
- `compiler_crash` when the Zig compiler process crashes, panics, or terminates abnormally while compiling a syntactically valid mutant
- `invalid` only when zentinel generated a syntactically malformed patch or violated its own mutator contract

Expected compile behavior in this document controls reporting language, not whether the candidate exists.

When AST syntax alone cannot prove an optional/null, error-path, errdefer, integer-boundary, or loop-boundary rewrite preserves Zig grammar, the mutator must filter the candidate before execution rather than emitting a `compile_error` result. `compile_error` is reserved for a syntactically well-formed candidate patch that Zig rejects during the normal mutant run.

## Equivalent Mutants

zentinel does not automatically remove mutants solely because they may be equivalent. Equivalent risk is reported as metadata and can be used by AI explanation flows.

Future deterministic equivalent filters must be:

- documented in this file
- proven by tests
- disabled by default until reviewed
- reported as `skipped` with reason `deterministic_equivalent_filter`
