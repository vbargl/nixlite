# nixlite — initial scaffold + `importTree`

Date: 2026-04-17
Status: Approved

## Purpose

Create `nixlite`, a personal Nix flake library exposing reusable helpers for use across other flake repos. First helper: `importTree`, which auto-generates a keyed attrset from a directory of Nix files, replacing the ad-hoc `discoverModules` used in `nixfiles/lib/default.nix`.

## Scope

1. Scaffold `/home/vbargl/personal/nixlite/` as a plain Nix flake library.
2. Initialize VCS: jj colocated with git.
3. Implement `importTree` and expose it via `flake.lib`.

Out of scope (explicit): flake-parts, packages, modules, overlays, additional helpers, tests (added later as needs arise).

## Repository layout

```
nixlite/
├── .jj/ + .git/            # jj colocated with git
├── .gitignore              # result, result-*, .direnv
├── flake.nix               # plain flake, nixpkgs input only
└── lib/
    ├── default.nix         # { lib }: { importTree = ...; }
    └── import-tree.nix     # importTree implementation
```

## flake.nix

Plain flake. Single input (`nixpkgs`, `nixos-25.11`). Single output: `lib = import ./lib { lib = nixpkgs.lib; }`.

```nix
{
  description = "Personal Nix library helpers.";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
  outputs = { self, nixpkgs }: {
    lib = import ./lib { lib = nixpkgs.lib; };
  };
}
```

Consumer usage:

```nix
inputs.nixlite.url = "github:vbargl/nixlite";
# ...
let tree = inputs.nixlite.lib.importTree ./machines/modules; in ...
```

## `importTree`

### Signature

```
importTree : Path -> AttrSet
```

### Rules

1. File `foo.nix` (where `foo != "default"`) → key `foo`, value `import ./foo.nix`.
2. Directory `bar/` containing `default.nix` → key `bar`, value `import ./bar` (which resolves to `./bar/default.nix`). Other files inside `bar/` are ignored — `default.nix` is an explicit override.
3. Directory `bar/` without `default.nix` → key `bar`, value produced by recursively applying these same rules to `bar/`.
4. Non-`.nix` files → ignored.
5. `default.nix` at the root of the passed directory → not added as a key (matches current `discoverModules` behavior).

### Semantics

- Values are **imported**, not paths. Works uniformly for modules (functions) and plain attrsets.
- Deterministic: output depends only on directory contents.
- No collision handling needed — the rules cannot produce collisions.

### Implementation approach (approved: A)

Single recursive function using `builtins.readDir` plus `lib.{hasSuffix, removeSuffix, filterAttrs, mapAttrs', nameValuePair}`. Expected size: ~15 lines. Lives in `lib/import-tree.nix`, wired into `lib/default.nix`.

Pseudocode:

```
importTree = dir:
  let entries = builtins.readDir dir;
      isNixFile = name: type: type == "regular" && hasSuffix ".nix" name && name != "default.nix";
      isDir     = name: type: type == "directory";
      hasDefault = subdir: (readDir subdir) ? "default.nix";
      files = filterAttrs isNixFile entries;
      dirs  = filterAttrs isDir     entries;
  in
     (mapAttrs' (n: _: nameValuePair (removeSuffix ".nix" n) (import (dir + "/${n}"))) files)
  // (mapAttrs  (n: _: let sub = dir + "/${n}";
                      in if hasDefault sub then import sub else importTree sub) dirs);
```

### Out of scope (noted for later)

- `_`-prefix WIP exclusion (vic-style).
- `.filter` / `.map` chainable API.
- Custom key transformers.

## Migration path (not part of this task)

`nixfiles/lib/default.nix` can later replace `discoverModules` with `nixlite.lib.importTree`. Depth-1 callers (`flake.modules.homeManager`, `flake.modules.nixos`) keep their shape; nested subdirs gain nested attrsets where they drop their `default.nix`.

## Decision log

- Plain flake (no flake-parts): only one output, no systems needed.
- Values imported, not paths: works for both module-functions and plain attrsets.
- Keep keyed-attrset design; do not adopt `vic/import-tree`. Preserves explicit `with self.modules.homeManager; [dev daily]` selection in `machines/`.
- jj colocated with git: matches `nixfiles` pattern, keeps GitHub compatibility.
- No LICENSE/README in this task; add when publishing.
