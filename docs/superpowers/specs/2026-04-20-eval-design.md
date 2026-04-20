# nixlite — `eval`

Date: 2026-04-20
Status: Approved

## Purpose

Port the module-evaluation capability from `github:vbargl/nix-lite` (`src/modules.nix` — `eval`) into `nixlite`, stripped to the minimum needed for personal use. The prior spec (`2026-04-17-merge-and-import-design.md`) explicitly deferred this; it is now back in scope, without priorities.

The result is a tiny NixOS-module-system-flavoured evaluator: expand a tree of modules into a single attrset, using the existing `nixlite.merge` to combine them.

## Scope

Add to `/home/vbargl/personal/nixlite/`:

- `lib/eval.nix` — exports `eval`
- Update `lib/default.nix` to include `eval` alongside `merge` / `mergeAll` / `import`

Expose `nixlite.eval` at the flake top level (matches the flattening done in `9fa1e7c`).

**Out of scope (as in the prior spec):** priorities (`default`/`force`/`prioval`), `systems.for`/`each`, last-wins / override semantics.

## Signature

```
eval : { inputs ? {}, module } -> AttrSet
```

- `inputs` — attrset. Its keys are spread as extra arguments to every function module, alongside `self`. Defaults to `{}`.
- `module` — the root module. See *Module shapes* below.

Attrset-argument form only (no positional variant). Unknown keys throw:

```
nixlite.eval: unknown key '<k>' in argument attrset
```

`module` is required; missing → throw.

## Module shapes

| Context | Allowed shapes |
|---|---|
| Top-level `module` argument | attrset, list, function |
| Inside a list (including `imports`) | path, attrset, function, list |

Paths are **only valid inside a list** (including the `imports` field of an attrset module). A bare path as the top-level `module` throws.

### Attrset modules

- `imports` (if present) must be a list. Its elements are further modules and get expanded into the module graph. `imports` is **stripped** from the payload and does not appear in the final merged result.
- All other keys form the module's payload and are merged via `nixlite.merge` with every other module's payload.

### List modules

- Every element is itself a module (subject to the shapes allowed "inside a list").
- All elements are expanded and their payloads merged.

### Function modules

- Called with `{ self, ...inputs }`:
  - `self` — the final merged result (fixpoint; see below).
  - The keys from the caller's `inputs` attrset, spread flat.
- If `inputs` contains a key named `self`, throw: `nixlite.eval: 'self' is reserved and cannot appear in inputs`.
- The function's return value is re-interpreted as a module (same rules as in-list shapes, minus "path" — a function returning a path is not supported).

### Path modules (lists only)

- Imported via `builtins.import` and the result is re-interpreted as a module.
- Paths are deduplicated within a single `eval` call: the second and subsequent occurrences of the same path are silently skipped (they contribute nothing).

## Merging

Uses `nixlite.merge` / `nixlite.mergeAll` verbatim — no priorities, no last-wins. Primitive conflicts throw with the standard `nixlite.merge: conflict at .path (a vs b)` message. Type mismatches throw `nixlite.merge: incompatible types at .path (ta vs tb)`.

Implication: every module must contribute strictly compatible primitives at any shared attribute path. This is the explicit design choice — rely on disjoint contributions, not override semantics.

## Fixpoint (`self`)

Implemented with `lib.fix` (or an inlined equivalent) over the merge step, matching the pattern in nix-lite's `eval`:

```
result = fix (self:
  let payloads = expand { inherit self; ...inputs } [ module ];
  in  mergeAll payloads)
```

A function module can reference `self.a.b` to read what other modules contribute, as long as the reference is not demanded during the expansion phase (standard module-system rule — infinite recursion if demanded eagerly).

## Expansion algorithm

Iterative (not recursive over module shapes), to keep cycle-skipping simple. Pseudocode:

```
expand args pending =
  loop with
    importedPaths = []
    payloads = []
    pending
  until pending == []:
    head = pending[0]
    rest = pending[1..]
    match head:
      function f   -> pending := [f args] ++ rest
      path p       -> if p in importedPaths: pending := rest
                      else: importedPaths += p; pending := [import p] ++ rest
      list xs      -> pending := xs ++ rest
      attrset a    -> imports = a.imports or []
                      payload = removeAttrs a ["imports"]
                      payloads += payload
                      pending := imports ++ rest
      other        -> throw
  return payloads
```

Then `mergeAll payloads` is the final result.

## Errors (`nixlite.eval:` prefix)

Each pending item carries a context flag (`allowPath`) that records whether it came from a list / `imports` (paths allowed) or from a function return / path-import result (paths not allowed). The error messages are phrased in terms of that context:

- Argument not an attrset: `nixlite.eval: expected attrset argument, got <type>`
- Unknown key in argument attrset: `nixlite.eval: unknown key '<k>' in argument attrset`
- Missing required key `module`: `nixlite.eval: missing required key 'module' in argument attrset`
- Caller `inputs` contains `self`: `nixlite.eval: 'self' is reserved and cannot appear in inputs`
- Top-level root is neither attrset/list/function (including: a bare path): `nixlite.eval: expected attrset/list/function at root, got <type>`
- Inside a list / `imports` — element is not one of path/attrset/function/list: `nixlite.eval: expected path/attrset/function/list, got <type>`
- Function return or path-import result is not a non-path module shape: `nixlite.eval: expected attrset/function/list, got <type>`
- Attrset `imports` field is not a list: `nixlite.eval: 'imports' must be a list, got <type>`
- Merge conflicts bubble through unchanged with `nixlite.merge:` prefix.

The "function / path-file returned a path" case deliberately reuses the generic `expected attrset/function/list, got path` message. It covers both (a) a function module whose return value is a path, and (b) a `.nix` file that, when `builtins.import`ed from a list, evaluates to another path.

## File layout after this change

```
nixlite/
├── flake.nix
└── lib/
    ├── default.nix   # { merge, mergeAll, import, eval }
    ├── merge.nix
    ├── import.nix
    └── eval.nix      # new
```

## Testing strategy (`lib.runTests`, same harness as `merge`/`import`)

1. **Attrset root**
   - No `imports`, simple payload → that payload.
   - With `imports = [ m1 m2 ]`, `imports` stripped and payloads merged.
   - Nested `imports` inside imported attrsets.
2. **List root**
   - List of attrsets merged.
   - List containing another list (recursive flatten).
   - List containing a function (applied then merged).
3. **Function root**
   - Function returns attrset — merged.
   - Function uses `self` to read another module's contribution.
   - Function uses `inputs` (e.g. `{ flake }`) spread.
4. **Paths (inside lists)**
   - Path imports and contributes its payload.
   - Same path in two places → contributes once (dedup).
   - Path whose import yields a function → function applied.
5. **Errors**
   - Bare path as root throws.
   - Non-module inside a list throws.
   - Function module returns a path → throws.
   - `inputs` with `self` key → throws.
   - `imports` not a list → throws.
   - Unknown top-level arg key → throws.
   - Missing `module` key → throws.
   - Two modules contributing conflicting primitives → `nixlite.merge:` error bubbles.

Tests go in a new `tests/eval.nix` plus wired into `tests/default.nix` so `nix flake check` runs them.

## Decision log

- Attrset-arg form only (Q4 → C). Matches the `import` API and is extensible.
- No priorities (Q1 → B). User prefers strict merge; modules must contribute disjoint primitives.
- Module args `{ self, ...inputs }` flat (Q3/Q4 clarifications). Differs from nix-lite's nested `inputs` attr.
- `imports` is special and stripped (Q5 → A). NixOS-style.
- Paths dedup silently (Q6 → A). Matches nix-lite; avoids surprise list-doubling.
- Paths only allowed inside lists (user's Q2 response). A path returning a module must be wrapped in a list (or `imports`), never passed as `module` directly.
