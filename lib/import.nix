{ lib }:
let
  inherit (builtins)
    readDir readFileType isPath isAttrs isList isFunction typeOf
    filter elem attrNames baseNameOf concatMap head;
  inherit (lib) hasSuffix removeSuffix filterAttrs mapAttrs mapAttrs' nameValuePair;

  apply = resolve: v:
    if resolve.hasResolve && isFunction v then v resolve.value else v;

  isNixFile = name: type: type == "regular" && hasSuffix ".nix" name;
  isDir = _: type: type == "directory";

  # Attrset form: walk directory, every .nix file becomes a key, every
  # subdirectory recurses. `default.nix` is treated as any other file.
  walkNested = resolve: dir:
    let
      entries = readDir dir;
      files = filterAttrs isNixFile entries;
      dirs = filterAttrs isDir entries;

      fileAttrs = mapAttrs'
        (name: _: nameValuePair (removeSuffix ".nix" name) (apply resolve (import (dir + "/${name}"))))
        files;

      dirAttrs = mapAttrs (name: _: walkNested resolve (dir + "/${name}")) dirs;
    in
    fileAttrs // dirAttrs;

  # Flat form: walk path into a list of file values, in attrName-sorted order.
  # Accepts either a directory (walked recursively) or a single .nix file.
  walkFlat = resolve: path:
    let t = readFileType path; in
    if t == "directory" then
      let
        entries = readDir path;
        step = name:
          let
            entryType = entries.${name};
            p = path + "/${name}";
          in
          if isNixFile name entryType then
            [ (apply resolve (import p)) ]
          else if isDir name entryType then
            walkFlat resolve p
          else
            [ ];
      in
      concatMap step (attrNames entries)
    else if t == "regular" && hasSuffix ".nix" (baseNameOf path) then
      [ (apply resolve (import path)) ]
    else
      [ ];

  # For a list of paths with flatten = true: each element (file or directory)
  # is walked flat; results are concatenated in the order given. Non-path
  # elements throw.
  walkListFlat = resolve: paths:
    concatMap
      (p:
        if isPath p then walkFlat resolve p
        else throw "nixlite.import: list element must be a path, got ${typeOf p}")
      paths;

  validKeys = [ "path" "resolve" "flatten" ];

  nixliteImport = arg:
    if isPath arg then
      walkNested { hasResolve = false; value = null; } arg
    else if isAttrs arg then
      let
        unknown = filter (k: !(elem k validKeys)) (attrNames arg);
      in
      if unknown != [ ] then
        throw "nixlite.import: unknown key '${head unknown}' in argument attrset"
      else if !(arg ? path) then
        throw "nixlite.import: missing required key 'path' in argument attrset"
      else
        let
          flatten = arg.flatten or false;
          resolve = { hasResolve = arg ? resolve; value = arg.resolve or null; };
          p = arg.path;
        in
        if isList p then
          if !flatten then
            throw "nixlite.import: 'path' as a list requires flatten = true"
          else
            walkListFlat resolve p
        else if isPath p then
          if flatten then walkFlat resolve p
          else walkNested resolve p
        else
          throw "nixlite.import: 'path' must be a path or list of paths, got ${typeOf p}"
    else
      throw "nixlite.import: expected path or attrset, got ${typeOf arg}";
in
nixliteImport
