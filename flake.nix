{
  description = "NixOS fleet configuration for the work ThinkPads";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      mkHost = { user, modules }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { primaryUser = user; };
          modules = [ ./modules/common.nix ] ++ modules;
        };
    in
    {
      nixosConfigurations = {
        p50 = mkHost {
          user = "iindesa";
          modules = [ ./hosts/p50/configuration.nix ];
        };

        t440s = mkHost {
          user = "rocio";
          modules = [ ./hosts/t440s/configuration.nix ];
        };

        x1-9thgen = mkHost {
          user = "iindesa";
          modules = [ ./hosts/x1-9thgen/configuration.nix ];
        };
      };

      checks.${system}.inventory-script = pkgs.runCommand "check-nixos-inventory-script" {
        nativeBuildInputs = [ pkgs.bash pkgs.shellcheck ];
      } ''
        bash -n ${./nixos-inventory.sh}
        shellcheck ${./nixos-inventory.sh}
        touch $out
      '';
    };
}
