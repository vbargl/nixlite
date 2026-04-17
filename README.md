# nixlite

Small personal Nix flake library. Three helpers exposed at the top level of the flake (`nixlite.merge`, `nixlite.mergeAll`, `nixlite.import`):

| Name        | Type                                    | Purpose                                                  |
|-------------|-----------------------------------------|----------------------------------------------------------|
| `merge`     | `a -> b -> merged`                      | Deep-merge two values (attrsets recurse, lists concat).  |
| `mergeAll` | `[x] -> merged`                         | Fold `merge` over a list.                                |
| `import`    | `(Path | { path; resolve? }) -> AttrSet` | Walk a directory into a keyed attrset, optionally applying a resolver to leaf functions. |

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

Walks a directory into a keyed attrset.

```
dir/
├── default.nix       # NOT added as a key (root default.nix is ignored)
├── foo.nix           # → { foo = import ./foo.nix; }
├── bar/
│   ├── default.nix   # → { bar = import ./bar; }  (dir collapses)
│   └── other.nix     # ignored (sibling of default.nix)
└── baz/
    └── qux.nix       # → { baz = { qux = import ./baz/qux.nix; }; }
```

Called two ways:

```nix
# 1. Path form — walk only, leaves kept as-is (functions stay functions).
nixlite.import ./modules

# 2. Attrset form — walk + apply `resolve` to any leaf that is a function.
nixlite.import { path = ./modules; resolve = { inherit flake; }; }
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

Unknown keys in the attrset form, missing `path`, or a non-path/non-attrset argument all throw.

## Tests

```
nix flake check
```

45 tests via `lib.runTests`, wired into `checks.x86_64-linux.tests`. Failures are printed as JSON to stderr.

## Layout

```
nixlite/
├── flake.nix
├── lib/
│   ├── default.nix
│   ├── merge.nix        # merge, mergeAll
│   └── import.nix       # unified import
└── tests/
    ├── default.nix
    └── fixtures/        # deterministic tree used by import tests
```
