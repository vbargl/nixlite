{
  description = "Personal Nix library helpers.";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      nixlite = import ./lib { inherit lib; };
      forSystems = f: lib.genAttrs [ "x86_64-linux" ] (system: f nixpkgs.legacyPackages.${system});
    in
    nixlite // {
      checks = forSystems (pkgs:
        let
          result = import ./tests { inherit lib nixlite; };
        in
        {
          tests = pkgs.runCommand "nixlite-tests"
            {
              failures = builtins.toJSON result.failures;
              pass = result.pass;
            }
            ''
              if [ "$pass" = "1" ]; then
                echo "all tests pass"
                touch "$out"
              else
                echo "FAILURES:" >&2
                echo "$failures" >&2
                exit 1
              fi
            '';
        });
    };
}
