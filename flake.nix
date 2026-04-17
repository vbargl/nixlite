{
  description = "Personal Nix library helpers.";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }: {
    lib = import ./lib { lib = nixpkgs.lib; };
  };
}
