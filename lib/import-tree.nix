{ lib }:
let
  inherit (builtins) readDir;
  inherit (lib) hasSuffix removeSuffix filterAttrs mapAttrs mapAttrs' nameValuePair;

  importTree = dir:
    let
      entries = readDir dir;

      isNixFile = name: type:
        type == "regular" && hasSuffix ".nix" name && name != "default.nix";
      isDir = _: type: type == "directory";

      files = filterAttrs isNixFile entries;
      dirs = filterAttrs isDir entries;

      fileAttrs = mapAttrs'
        (name: _: nameValuePair (removeSuffix ".nix" name) (import (dir + "/${name}")))
        files;

      dirAttrs = mapAttrs
        (name: _:
          let
            sub = dir + "/${name}";
            hasDefault = (readDir sub) ? "default.nix";
          in
          if hasDefault then import sub else importTree sub)
        dirs;
    in
    fileAttrs // dirAttrs;
in
importTree
