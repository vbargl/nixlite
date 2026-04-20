# nixlite

Small personal Nix flake library. Four helpers exposed at the top level of the flake (`nixlite.merge`, `nixlite.mergeAll`, `nixlite.import`, `nixlite.eval`):

| Name        | Type                                    | Purpose                                                  |
|-------------|-----------------------------------------|----------------------------------------------------------|
| `merge`     | `a -> b -> merged`                      | Deep-merge two values (attrsets recurse, lists concat).  |
| `mergeAll` | `[x] -> merged`                         | Fold `merge` over a list.                                |
| `import`    | `(Path \| [Path] \| { path; resolve?; flatten?; expandDir? }) -> AttrSet \| [value]` | Walk a directory into a keyed attrset (collapsing subdirs that contain `default.nix`, like native Nix). `flatten = true` returns a flat list. `expandDir = true` disables the collapse. List-of-paths returns a concatenated list. |
| `eval`      | `{ inputs?; module } -> AttrSet`        | Lightweight NixOS-module-style evaluator — expands an `imports` tree, applies modules with `self` fixpoint, merges with `merge`. |

## Install

```nix
{
  inputs.nixlite.url = "github:vbargl/nixlite";

  outputs = { self, nixpkgs, nixlite, ... }: {
    # use nixlite.merge / mergeAll / import here
  };
}
```

## `merge` / `mergeAll`

Deep-merge respecting types.

```nix
nixlite.merge
  { services.web = { port = 8080; hosts = [ "a" ]; }; }
  { services.web = { tls = true;  hosts = [ "b" ]; }; }
# => { services.web = { port = 8080; tls = true; hosts = [ "a" "b" ]; }; }

nixlite.mergeAll [
  { a = 1; }
  { b = 2; }
  { c = 3; }
]
# => { a = 1; b = 2; c = 3; }
```

Rules:

| Left        | Right       | Result                                      |
|-------------|-------------|---------------------------------------------|
| attrset     | attrset     | key-wise recursive merge                    |
| list        | list        | `left ++ right`                             |
| null        | anything    | take `right` (and mirror for `X × null`)    |
| primitive   | primitive   | equal → value; **unequal → throw**          |
| any mismatch (attrset × list, function × x, …) | | **throw** |

Throws include the attribute path:

```
nixlite.merge: conflict at .services.web.port (8080 vs 9090)
nixlite.merge: incompatible types at .hosts (list vs set)
```

## `import`

Walks a directory into a keyed attrset. Matches `builtins.import`'s native behavior: a directory containing `default.nix` collapses to that import (siblings of `default.nix` are not walked).

```
dir/
├── foo.nix           # → { foo = import ./foo.nix; }
├── bar/
│   ├── default.nix   # → { bar = import ./bar; }  (dir collapses)
│   └── other.nix     # ignored (sibling of default.nix)
└── baz/
    └── qux.nix       # → { baz = { qux = import ./baz/qux.nix; }; }
```

Called three ways:

```nix
# 1. Path form — walk only, leaves kept as-is (functions stay functions).
nixlite.import ./modules

# 2. Attrset form — walk + apply `resolve` to any leaf that is a function.
nixlite.import { path = ./modules; resolve = { inherit flake; }; }

# 3. List-of-paths form — each path walked; results concatenated into a list.
nixlite.import [ ./modules ./extras ./one-file.nix ]
```

Resolve is applied **once** per leaf. Non-function leaves pass through untouched.

Typical use inside a NixOS module:

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

### `flatten`

Return a flat list of leaf values instead of a keyed attrset:

```nix
nixlite.import { path = ./modules; flatten = true; }
# → [ leaf1 leaf2 ... ]  (attrName-sorted within each level)
```

A directory that collapses (contains `default.nix`) contributes a single element — its `import`ed value.

The list-of-paths form always returns a list (flatten is implicit for lists):

```nix
nixlite.import [ ./a.nix ./subtree ]
# → [ (import ./a.nix) ... items from ./subtree ... ]
```

### `expandDir`

Opt out of the `default.nix` collapse — every `.nix` file (including `default.nix`) becomes a key, and every subdirectory is walked:

```nix
nixlite.import { path = ./dir; expandDir = true; }
# A subdir bar/ with default.nix and other.nix becomes:
#   bar = { default = import ./dir/bar/default.nix; other = import ./dir/bar/other.nix; };
```

Works with `flatten` too — with both on, `default.nix` and every sibling contribute their own leaf.

Unknown keys in the attrset form, missing `path`, non-path/list/attrset arguments, or list elements that aren't paths all throw.

## `eval`

Expand a module tree and merge it via `nixlite.merge`. Minimal analogue of NixOS module evaluation — no options system, no priorities. Primitive conflicts throw.

```nix
nixlite.eval {
  inputs = { flake = self; };
  module = {
    imports = [
      ./module-a.nix            # path — imported and treated as a module
      { services.web.port = 8080; }
      ({ self, flake, ... }: {  # function — gets { self, ...inputs }
        services.web.hosts = [ flake.outPath ];
      })
    ];
  };
}
```

A module is one of:

| Context | Allowed shapes |
|---|---|
| Top-level `module` | attrset, list, function |
| Inside a list (including `imports`) | path, attrset, function, list |

- **attrset** — `imports` (if present) must be a list of modules; it is stripped from the final result. Every other key becomes part of the payload.
- **list** — every element is itself a module (shapes per "inside a list" above).
- **function** — called with `{ self, ...inputs }` where `self` is the fully-merged final result (fixpoint). Return value is treated as another module.
- **path** — imported via `builtins.import`. The imported value is treated as a module (shapes per function-return rules — paths inside paths are not allowed). Paths are deduplicated within a single `eval` call.

Merging uses `nixlite.merge` as-is: no priorities, strict on primitive conflicts. Every module must contribute disjoint primitives at any shared attribute path.

`inputs` may not contain a key named `self` (reserved). Unknown keys in the argument attrset throw. Bare paths at the top level throw.

## Tests

```
nix flake check
```

88 tests via `lib.runTests`, wired into `checks.x86_64-linux.tests`. Failures are printed as JSON to stderr.

## Layout

```
nixlite/
├── flake.nix
├── lib/
│   ├── default.nix
│   ├── merge.nix        # merge, mergeAll
│   ├── import.nix       # unified import
│   └── eval.nix         # module-tree evaluator
└── tests/
    ├── default.nix
    ├── eval.nix
    ├── fixtures/        # deterministic tree used by import tests
    ├── fixtures-flat/   # clean fixture used by flatten tests
    └── eval-fixtures/   # module fixtures used by eval tests
```
