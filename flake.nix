{
  description = "NixOS fleet configuration for the work ThinkPads";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
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
    };
}
