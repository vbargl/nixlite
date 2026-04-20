# nixlite — `import`: uniform collapse + `expandDir` + list shorthand

Date: 2026-04-20
Status: Approved

> Supersedes `2026-04-20-import-flatten-and-drop-default-special-case.md`. That spec removed `default.nix` special-casing entirely; the user then decided the native-Nix behavior (dir-with-default collapses) should be the default, with an opt-out flag.

## Purpose

1. Revert the walk behavior so it matches `builtins.import`: a directory containing `default.nix` **collapses** to `builtins.import ./thatDir` (its siblings are not walked). Applies uniformly — including the root passed to `nixlite.import`.
2. Add **`expandDir = true`** as an opt-out: when set, directories are always walked in full, `default.nix` becomes a regular `default` key, siblings are kept.
3. Accept a **list of paths at the top level**: `nixlite.import [ p1 p2 ]`. Each element is walked (with the collapse rule, unless `expandDir`) and the results are concatenated into a flat list. No explicit `flatten` is required — list input always implies list output.

`flatten = true` from the prior spec stays: it converts a single-path walk into a flat list of leaves, honoring the collapse rule (a collapsing dir contributes one leaf).

## Scope

Edit `/home/vbargl/personal/nixlite/`:

- `lib/import.nix` — rewrite walk to collapse on `default.nix`; add `expandDir` option; accept list of paths at top level and in `path`.
- `tests/default.nix` — revert the `default-is-normal` tests to collapse expectations; add `expandDir` tests; add list-shorthand tests.
- `tests/fixtures/default.nix` — delete (was only there to test root exclusion, no longer needed).
- `README.md` — rewrite `import` section to reflect the restored collapse + new flags.

Out of scope: any change to `merge`, `mergeAll`, `eval`.

## Signature

```
import : ( Path
         | [ Path ]
         | { path      : Path | [ Path ]
           , resolve?  : Any
           , flatten?  : Bool   # default false
           , expandDir?: Bool   # default false
           }
         )
       -> AttrSet | [ value ]
```

Top-level shorthand:
- `import p`      ≡ `import { path = p; }`
- `import [ .. ]` ≡ `import { path = [ .. ]; }`

## Walk semantics

A **directory collapses** when it contains a `default.nix` AND `expandDir = false`. When a directory collapses, its value in the output is `apply resolve (builtins.import ./thatDir)` — a single value, no further walking.

### Single path, attrset output (default)

`import ./dir` or `import { path = ./dir; }`:

- If `./dir` collapses at the root → return its single import value (the top-level result is not an attrset in this case — matches what a caller would get from `builtins.import ./dir`).
- Otherwise walk the dir:
  - Each `X.nix` file → key `X` with value `apply resolve (import X.nix)`.
  - Each subdirectory `Y/`:
    - If `Y` collapses → one leaf value.
    - Otherwise recurse.

### Single path, flat output (`flatten = true`)

`import { path = ./dir; flatten = true; }`:

- If `./dir` collapses → `[ <import value> ]` (one element).
- Otherwise walk the dir, concatenating leaves in `attrNames`-sorted order. Collapsing subdirs each contribute one element; non-collapsing ones recurse-and-concat.
- A single `.nix` file path is allowed here too → `[ (import p) ]`.

### List of paths (always flat)

`import [ p1 p2 ]` or `import { path = [ p1 p2 ]; }`:

- Each element must be a `Path`.
- If an element is a directory → walk flat (collapse-aware).
- If an element is a `.nix` file → `[ (import p) ]`.
- Results are concatenated in the given list order.
- `flatten` has no effect here; list input implies list output.

## `expandDir = true`

Disables the collapse rule at *every* level of the walk. Every `.nix` file (including `default.nix`) becomes a key; every subdirectory is always recursed into. Pair with `flatten = true` for a recursive-flat list of every leaf.

## Errors (`nixlite.import:` prefix)

- Unknown key in argument attrset: `nixlite.import: unknown key '<k>' in argument attrset`
- Missing `path`: `nixlite.import: missing required key 'path' in argument attrset`
- Argument is none of `Path`, `[Path]`, or attrset: `nixlite.import: expected path, list of paths, or attrset, got <type>`
- `path` field in attrset form is neither path nor list: `nixlite.import: 'path' must be a path or list of paths, got <type>`
- List element (shorthand or attrset form) is not a path: `nixlite.import: list element must be a path, got <type>`

## Testing strategy

Assumes `tests/fixtures/` with `default.nix` removed. Relevant fixtures:

- `fixtures/fn.nix` — function
- `fixtures/plain.nix` — attrset
- `fixtures/dir-recurse/` — no `default.nix`; recurses
- `fixtures/dir-with-def/default.nix` — a function (collapses the dir)
- `fixtures/dir-with-def/ignored.nix` — sibling, should be ignored under collapse
- `fixtures/root-default-sibling/default.nix` — simple attrset (collapses)
- `fixtures-flat/` — `a.nix`, `b.nix`, `sub/c.nix`; no `default.nix`

Tests:

**Attrset output (collapse default)**

- `import_pathFormKeys` — no `default` key at top level, no `ignored` inside `dir-with-def`.
- `import_dirWithDefCollapsed` — `noResolve."dir-with-def"` is a function.
- `import_dirWithDefIgnoresSiblings` — applying it yields `{ dirFn = args; }` with no `ignored`.
- `import_rootDefaultSiblingCollapsed` — `{ collapsed = true; }`.
- `import_dirRecurseHasSub` — `[ "other" "sub" ]`.
- `import_nestedFnStaysFunction`, `import_nestedNonFnPassthrough`, `import_plainPassthrough`, `import_fnStaysFunction`.

**Resolve variants (unchanged signatures, collapsed targets)**

- `importR_dirWithDefApplied` — `{ dirFn = { tag = "R"; }; }` (function at collapse site applied with `resolve`).
- `importR_nestedFnApplied`, `importR_nonFnUntouched`, `importR_plainUntouched`, `importR_fnApplied`.

**expandDir**

- `import_expandDirExposesDefaultAsKey` — `dir-with-def.default` is a function.
- `import_expandDirExposesSiblings` — `dir-with-def.ignored` is the attrset.
- `import_expandDirRootDefaultSiblingWalked` — `root-default-sibling.default` exists.

**flatten (single path)**

- `import_flattenSinglePath` — flat over `fixtures-flat`.
- `import_flattenCollapseDirLength` + `import_flattenCollapseDirFirstIsFunction` — flatten of `dir-with-def` yields one element (the function).
- `import_flattenWithExpandDir` — flatten + expandDir + resolve over `dir-with-def` yields `[ { dirFn = ... } { must = ... } ]`.
- `import_flattenWithResolveNoOp` — resolve over fixtures-flat is a no-op.

**list-of-paths (shorthand and attrset form)**

- `import_listShorthandFiles` — list of `.nix` files.
- `import_listShorthandDirs` — list of dirs.
- `import_listShorthandMixed` — mixed.
- `import_listShorthandCollapseLen` — two collapsing dirs give two elements.
- `import_listAttrsFormFiles` — same behavior as shorthand via `{ path = [..]; }`.
- `import_listAttrsFormWithResolve` — resolve applies under list form.

**errors**

- `import_throwsUnknownKey`, `import_throwsMissingPath`, `import_throwsBadArg`, `import_throwsNullArg` — unchanged.
- `import_throwsBadPathType` — non-path-non-list `path` throws.
- `import_throwsListWithNonPathElement` — shorthand with a non-path element.
- `import_throwsListAttrsWithNonPathElement` — attrset-form list with a non-path element.

Total: 88 (up from 82; added 10 new, removed some that were obsolete under the reverted behavior).

## Decision log

- Uniform collapse at every level including root (user explicitly: "I don't think root paths will have default.nix and if so it is expected").
- Name `expandDir` chosen over `collapseOnDefault`, `sparseDir`, etc. — reads as "directories expand instead of collapsing."
- List-of-paths implies flatten always — `flatten` on list paths is redundant and silently ignored (permissive).
- `flatten` on a single-path input still respects the collapse rule — a collapsing dir contributes exactly one leaf.
- Top-level shorthand `import [ .. ]` is the third accepted call shape alongside `import p` and `import { ... }`.
- Removed `tests/fixtures/default.nix` — under uniform collapse, its presence would collapse the root of `fixtures` to a single value and break every other test that reads `noResolve.*`. The old fixture existed specifically to verify root-exclusion, which is no longer a rule.
