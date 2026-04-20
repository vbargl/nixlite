{ lib }:
let
  mergeLib = import ./merge.nix { inherit lib; };
in
{
  inherit (mergeLib) merge mergeAll;
  import = import ./import.nix { inherit lib; };
  eval = import ./eval.nix { inherit lib; };
}
