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

  fileLeaf = opts: p: apply opts.resolve (import p);

  # A directory "collapses" when it contains default.nix and expandDir is off.
  dirCollapses = opts: dir: !opts.expandDir && (readDir dir) ? "default.nix";

  # Walk a directory into a keyed attrset. Subdirectories that collapse
  # (contain default.nix, expandDir = false) are replaced by their
  # builtins.import result.
  walkNested = opts: dir:
    let
      entries = readDir dir;
      files = filterAttrs isNixFile entries;
      dirs = filterAttrs isDir entries;

      fileAttrs = mapAttrs'
        (name: _: nameValuePair (removeSuffix ".nix" name) (fileLeaf opts (dir + "/${name}")))
        files;

      dirAttrs = mapAttrs
        (name: _:
          let sub = dir + "/${name}"; in
          if dirCollapses opts sub then apply opts.resolve (import sub)
          else walkNested opts sub)
        dirs;
    in
    fileAttrs // dirAttrs;

  # Walk a path (file or directory) into a flat list of leaf values.
  # A collapsing directory contributes one leaf (its builtins.import result).
  walkFlat = opts: path:
    let t = readFileType path; in
    if t == "directory" then
      if dirCollapses opts path then
        [ (apply opts.resolve (import path)) ]
      else
        let
          entries = readDir path;
          step = name:
            let
              entryType = entries.${name};
              p = path + "/${name}";
            in
            if isNixFile name entryType then [ (fileLeaf opts p) ]
            else if isDir name entryType then walkFlat opts p
            else [ ];
        in
        concatMap step (attrNames entries)
    else if t == "regular" && hasSuffix ".nix" (baseNameOf path) then
      [ (fileLeaf opts path) ]
    else
      [ ];

  # For a list of paths: each element (file or directory) is walked flat;
  # results are concatenated in the order given. Non-path elements throw.
  walkListFlat = opts: paths:
    concatMap
      (p:
        if isPath p then walkFlat opts p
        else throw "nixlite.import: list element must be a path, got ${typeOf p}")
      paths;

  # Top-level walk for a single path: if the root collapses (has default.nix
  # and expandDir is off), the whole call returns its builtins.import result.
  walkTop = opts: path:
    if dirCollapses opts path then apply opts.resolve (import path)
    else walkNested opts path;

  defaultOpts = {
    resolve = { hasResolve = false; value = null; };
    expandDir = false;
  };

  validKeys = [ "path" "resolve" "flatten" "expandDir" ];

  nixliteImport = arg:
    if isPath arg then
      walkTop defaultOpts arg
    else if isList arg then
      # Shorthand: list of paths → flat list of walks.
      walkListFlat defaultOpts arg
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
          opts = {
            resolve = { hasResolve = arg ? resolve; value = arg.resolve or null; };
            expandDir = arg.expandDir or false;
          };
          p = arg.path;
        in
        if isList p then
          # List path always returns a flat list; `flatten` is redundant.
          walkListFlat opts p
        else if isPath p then
          if flatten then walkFlat opts p
          else walkTop opts p
        else
          throw "nixlite.import: 'path' must be a path or list of paths, got ${typeOf p}"
    else
      throw "nixlite.import: expected path, list of paths, or attrset, got ${typeOf arg}";
in
nixliteImport
