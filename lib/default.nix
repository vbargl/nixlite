{ lib }:
let
  mergeLib = import ./merge.nix { inherit lib; };
in
{
  inherit (mergeLib) merge mergeList;
  import = import ./import.nix { inherit lib; };
}
