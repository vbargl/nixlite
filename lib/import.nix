{ lib }:
let
  inherit (builtins) readDir isPath isAttrs isFunction;
  inherit (lib) hasSuffix removeSuffix filterAttrs mapAttrs mapAttrs' nameValuePair;

  walk = resolve: dir:
    let
      entries = readDir dir;

      isNixFile = name: type:
        type == "regular" && hasSuffix ".nix" name && name != "default.nix";
      isDir = _: type: type == "directory";

      apply = v:
        if resolve.hasResolve && isFunction v then v resolve.value else v;

      files = filterAttrs isNixFile entries;
      dirs = filterAttrs isDir entries;

      fileAttrs = mapAttrs'
        (name: _: nameValuePair (removeSuffix ".nix" name) (apply (import (dir + "/${name}"))))
        files;

      dirAttrs = mapAttrs
        (name: _:
          let
            sub = dir + "/${name}";
            hasDefault = (readDir sub) ? "default.nix";
          in
          if hasDefault then apply (import sub) else walk resolve sub)
        dirs;
    in
    fileAttrs // dirAttrs;

  validKeys = [ "path" "resolve" ];

  nixliteImport = arg:
    if isPath arg then
      walk { hasResolve = false; value = null; } arg
    else if isAttrs arg then
      let
        unknown = builtins.filter (k: !(builtins.elem k validKeys)) (builtins.attrNames arg);
      in
      if unknown != [ ] then
        throw "nixlite.import: unknown key '${builtins.head unknown}' in argument attrset"
      else if !(arg ? path) then
        throw "nixlite.import: missing required key 'path' in argument attrset"
      else
        walk
          {
            hasResolve = arg ? resolve;
            value = arg.resolve or null;
          }
          arg.path
    else
      throw "nixlite.import: expected path or attrset, got ${builtins.typeOf arg}";
in
nixliteImport
