# nixlite — `merge`, `mergeList`, unified `import`

Date: 2026-04-17
Status: Approved

## Purpose

Extract two capabilities from `github:vbargl/nix-lite` into `nixlite`, simplified for personal use as NixOS module building blocks:

1. **Deep merge** of attrsets and lists, strict about primitive conflicts.
2. **Unified `import`** — replaces the existing `importTree` — walks a directory into a keyed attrset, with optional function resolution at leaves.

The full `nix-lite.modules.eval` (priorities, fixpoint, module-definition polymorphism with `imports`/list/path/function) is **not** ported. NixOS's own module system handles combining, so the user only needs (a) the merge primitive and (b) an importer that returns NixOS-consumable values.

## Scope

Add to `/home/vbargl/personal/nixlite/`:

- `lib/merge.nix` — `merge`, `mergeList`
- `lib/import.nix` — unified `import` (replaces `lib/import-tree.nix`)
- Update `lib/default.nix` to expose `merge`, `mergeList`, `import`

Remove: `lib/import-tree.nix` and the `importTree` export (replaced by `import`).

Out of scope: priorities (`default`/`force`), fixpoints (`self` in module functions), `systems.for`/`each`, module-definition resolver with `imports` field.

## `merge` / `mergeList`

### Signatures

```
merge     : a -> b -> merged
mergeList : [x] -> merged       # equivalent to builtins.foldl' merge {} xs
```

### Rules

| Left        | Right       | Result                                         |
|-------------|-------------|------------------------------------------------|
| attrset     | attrset     | key-wise recursive merge                       |
| list        | list        | `left ++ right`                                |
| null        | anything    | take `right` (including `null` → `null`)       |
| anything    | null        | take `left`                                    |
| primitive   | primitive   | equal → value; unequal → **throw**             |
| any mismatch (e.g. attrset × list, function × x) | | **throw** |

"Primitive" = bool, int, float, string, path. (null is handled separately by the rules above; functions are never mergeable.)

### Error messages

Include the attribute path into the structure and the conflicting values/types:

```
nixlite.merge: conflict at .services.web.port (8080 vs 9090)
nixlite.merge: incompatible types at .hosts (list vs set)
```

Path tracking is threaded through the recursion; the top-level call starts with path `""` (which renders as `<root>` in messages).

### Semantics notes

- `merge` is associative for the attrset and list cases; order within lists is preserved (left then right).
- `merge a a` should equal `a` for any input that doesn't contain a function.
- `mergeList []` → `{}` (identity for attrset merge). `mergeList [x]` → `x`.

## `import`

### Signature

```
import : (Path | { path : Path, resolve : Any }) -> AttrSet
```

### Dispatch

- `builtins.isPath arg` → path form (walk, no resolution).
- `builtins.isAttrs arg` → attrset form:
  - `path` field required; missing → throw.
  - `resolve` field optional; absent → no resolution; present → pass its value to any leaf that is a function.
  - Any other keys → throw (`nixlite.import: unknown key '<k>' in argument attrset`).
- Anything else → throw.

### Tree walk rules (unchanged from `importTree`)

1. File `foo.nix` (not `default.nix`) → key `foo`, value `import ./foo.nix`.
2. Directory `bar/` with `default.nix` → key `bar`, value `import ./bar`.
3. Directory `bar/` without `default.nix` → key `bar`, value produced by recursively applying the same rules.
4. Non-`.nix` files ignored.
5. Root `default.nix` of the passed directory → not a key (matches existing behavior).

### Leaf resolution (attrset form with `resolve`)

At each leaf value `v` obtained from rules 1 or 2 above:

- If `builtins.isFunction v` → replace with `v resolve`.
- Otherwise → leave `v` unchanged.

**Single application only.** If `v resolve` is itself a function, it stays a function. If the result is an attrset containing functions, those inner functions are not touched.

For nested directories walked via rule 3, the same resolution rule applies at each further leaf — the walk is recursive, so this naturally covers any depth.

### Consumer usage example (from CLAUDE.md-style NixOS module)

```nix
{ config, lib, flake, ... }:
let
  partials = nixlite.import { path = ./dir; resolve = { inherit flake; }; };
in {
  imports = [
    partials.module1
    partials.module2
  ];
}
```

## File layout after this change

```
nixlite/
├── flake.nix
└── lib/
    ├── default.nix   # { merge, mergeList, import }
    ├── merge.nix     # merge, mergeList
    └── import.nix    # unified import (replaces import-tree.nix)
```

`lib/import-tree.nix` is deleted.

## Testing strategy

Manual evaluation tests during implementation (no formal test harness, keeping this minimal):

1. `merge` basics: two disjoint attrsets, overlapping with attrset values (recurse), list-list concat, primitive-primitive equal, primitive-primitive unequal (throw), null absorption, type mismatch (throw).
2. `merge` error messages include path and values.
3. `mergeList []`, `mergeList [x]`, `mergeList [a b c]` equivalence with manual folds.
4. `import ./dir` — re-run the 5-rule test cases from the `importTree` spec.
5. `import { path = ./dir; resolve = ARGS; }` — verify functions get applied, non-functions passthrough, single-application rule.
6. `import { path = ./dir; }` (resolve omitted) — functions not applied.
7. `import { path = ./x; unknown = 1; }` — throws.
8. `import "not a path or attrset"` — throws.

## Decision log

- Drop priorities from merge — user asked for strict "throw on primitive conflict".
- Drop `importModule` (nix-lite-style module resolver) — NixOS's own `imports` handles composition; unified `import` + user's NixOS modules suffice.
- `import` replaces `importTree`. The path form is strictly a degenerate case of the new signature; no reason to keep two names.
- Name `import` despite being a Nix keyword — works fine as attr access (`nixlite.import ./x`), matches the user's own mental model from the brainstorming session.
- Single application for `resolve` — predictable, matches NixOS module pattern where modules-as-functions are applied once with module args.
- `null` absorbed (rather than treated as primitive that throws on mismatch) — user's explicit call during brainstorming.
- `mergeList` rather than `mergeAll` — user's naming preference.
