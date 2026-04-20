# nixlite — `import`: add `flatten`, drop `default.nix` special-case

Date: 2026-04-20
Status: Approved

## Purpose

Two changes to `nixlite.import`:

1. **Remove the `default.nix` special-case** that made a directory-with-`default.nix` collapse into `builtins.import ./dir` and excluded the root `default.nix` from the walk. `default.nix` is now treated as any other `.nix` file — it produces a `default` key at its level, siblings are walked normally, and the containing directory is walked normally.
2. **Add `flatten`** to the attrset form. When `flatten = true`, the result is a flat list of leaf values (instead of a keyed attrset). Paired with `path` being either a single path or a list of paths.

## Scope

Edit `/home/vbargl/personal/nixlite/`:

- `lib/import.nix` — rewrite walk to drop `default.nix` logic; add `walkFlat` + `walkListFlat`; extend `validKeys`.
- `tests/default.nix` — update affected import tests (see *Breaking changes*), add ≈ 10 new tests for flatten.
- `tests/fixtures-flat/` — new clean fixture tree (a.nix, b.nix, sub/c.nix) for flatten tests.
- `README.md` — update `import` section.

Out of scope: any change to `merge`, `mergeAll`, `eval`.

## Behavior — walk (attrset form)

For `nixlite.import ./dir` or `nixlite.import { path = ./dir; resolve? }`:

- Every file `X.nix` in the directory becomes a key `X` with value `builtins.import ./dir/X.nix` (optionally `resolve`-applied if it's a function). **This includes `default.nix`.**
- Every subdirectory `Y/` becomes a key `Y` with value produced by recursively applying the same rules. **No more "has default.nix → collapse".**

Attribute-name order is whatever `builtins.attrNames` produces (alphabetical).

## Behavior — flatten (list form)

New key: `flatten : bool`. Default `false`.

With `flatten = true`, `path` may be:

- **A single path** (file or directory).
  - Directory: walked flat — files contribute one list element each, subdirectories contribute the concatenation of their flat walk. Order: alphabetical by name at each level.
  - `.nix` file: contributes `[ (apply (import p)) ]`.
  - Other: contributes `[]`.
- **A list of paths.** Each element is walked flat as above and the results are concatenated in the order given by the list.

With `flatten = false` (default), `path` must be a single path (list form throws).

## Errors (`nixlite.import:` prefix)

Existing errors unchanged. New/adjusted:

- `path` is a list but `flatten` is not `true`: `nixlite.import: 'path' as a list requires flatten = true`
- `path` is neither a path nor a list: `nixlite.import: 'path' must be a path or list of paths, got <type>`
- A list element is not a path: `nixlite.import: list element must be a path, got <type>`
- Unknown keys still throw; `flatten` is added to the valid set.

## Breaking changes

These existing tests/behaviors change:

| Test / behavior | Before | After |
|---|---|---|
| Root `default.nix` | excluded from the walk | key `default` |
| Directory with `default.nix` | collapsed to `import ./dir` (function or attrset) | walked; `default` is one of its keys |
| Sibling of `default.nix` in a dir | ignored | included |

Tests updated (renamed where the assertion inverts):

- `import_rootDefaultExcluded` → `import_rootDefaultPresent`
- `import_dirWithDefStaysFunction` → `import_dirWithDefNowRecurses` + `import_dirWithDefDefaultStaysFunction`
- `import_dirWithDefIgnoresSiblings` → `import_dirWithDefSiblingPresent`
- `import_rootDefaultSiblingCollapsed` → `import_rootDefaultSiblingNotCollapsed`
- `importR_dirWithDefApplied` — path updated to `.dir-with-def.default`

## Testing strategy (`lib.runTests`)

New tests under `import_flatten*`:

- Single path → flat list in attrName order.
- List of `.nix` files → list of imports.
- List of directories → concatenation of each walkFlat.
- Mixed list (file + dir).
- Flatten with `resolve` — resolve applied to function leaves.
- Errors:
  - list path without flatten throws,
  - bad path type throws,
  - non-path list element throws.

Total: ~10 new tests, 82 total.

## Decision log

- Use `builtins.readFileType` (Nix 2.14+) to distinguish file vs directory in `walkFlat`. User is on modern Nix; fine.
- `flatten = true` with single path also works (not list-only) — user explicitly confirmed.
- List path requires `flatten = true` — no natural keying for list-of-dirs would be obvious.
- Ordering: alphabetical by `attrNames` within each directory, list order preserved across list elements. Deterministic and unsurprising.
