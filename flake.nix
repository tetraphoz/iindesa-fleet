{
  description = "NixOS fleet configuration for the work ThinkPads";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, agenix, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      mkHost = { user, modules }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit agenix; primaryUser = user; };
          modules = [ agenix.nixosModules.default ./modules/common.nix ] ++ modules;
        };
    in
    {
      nixosConfigurations = {
        p50 = mkHost {
          user = "iindesa";
          modules = [ ./hosts/p50/configuration.nix ];
        };

        t440s = mkHost {
          user = "iindesa";
          modules = [ ./hosts/t440s/configuration.nix ];
        };

        x1-9thgen = mkHost {
          user = "iindesa";
          modules = [ ./hosts/x1-9thgen/configuration.nix ];
        };
      };

      checks.${system}.inventory-script = pkgs.runCommand "check-fleet-shell-scripts" {
        nativeBuildInputs = [ pkgs.bash pkgs.shellcheck ];
      } ''
        for script in \
          ${./nixos-inventory.sh} \
          ${./scripts/install-x1.sh} \
          ${./scripts/update-x1.sh}; do
          bash -n "$script"
          shellcheck "$script"
        done
        touch $out
      '';
    };
}
