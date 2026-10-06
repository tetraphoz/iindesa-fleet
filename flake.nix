{
  description = "NixOS fleet configuration for IINDESA workstations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";
    nixos-anywhere.inputs.nixos-stable.follows = "nixpkgs";
    nixos-anywhere.inputs.disko.follows = "disko";
  };

  outputs = { nixpkgs, agenix, disko, nixos-anywhere, ... }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = import nixpkgs { inherit system; };

      # Add each active host once here. A diskDevice also opts the host into a
      # destructive <name>-install output using the shared Disko layout.
      fleetHosts = {
        p50 = {
          primaryUser = "iindesa";
          diskDevice = "/dev/nvme0n1";
          module = ./hosts/p50/configuration.nix;
        };
        x1-9thgen = {
          primaryUser = "iindesa";
          diskDevice = "/dev/nvme0n1";
          module = ./hosts/x1-9thgen/configuration.nix;
        };
      };

      mkHost = host: lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit agenix;
          primaryUser = host.primaryUser;
        };
        modules = [
          agenix.nixosModules.default
          ./modules/common.nix
          ./modules/storage.nix
          ./modules/restic-backup.nix
          host.module
        ];
      };

      mkInstallHost = host: lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit agenix;
          diskDevice = host.diskDevice;
          primaryUser = host.primaryUser;
        };
        modules = [
          agenix.nixosModules.default
          disko.nixosModules.disko
          ./modules/disko-layout.nix
          ./modules/common.nix
          ./modules/restic-backup.nix
          host.module
        ];
      };

      hostConfigurations = lib.mapAttrs (_: host: mkHost host) fleetHosts;
      installConfigurations = lib.mapAttrs' (name: host:
        lib.nameValuePair "${name}-install" (mkInstallHost host)
      ) (lib.filterAttrs (_: host: host ? diskDevice) fleetHosts);
    in
    {
      nixosConfigurations = hostConfigurations // installConfigurations;

      packages.${system} = {
        disko = disko.packages.${system}.disko;
        nixos-anywhere = nixos-anywhere.packages.${system}.default;
      };

      checks.${system}.shell-scripts = pkgs.runCommand "check-fleet-shell-scripts" {
        nativeBuildInputs = [ pkgs.bash pkgs.shellcheck ];
      } ''
        for script in \
          ${./nixos-inventory.sh} \
          ${./scripts/install-host.sh} \
          ${./scripts/deploy-host.sh}; do
          bash -n "$script"
          shellcheck "$script"
        done
        touch $out
      '';
    };
}
