# Operations

## Change and validate

Use the fleet checkout as the source of truth. Before activation, review
`git status` and the diff, then run:

```sh
nix flake check --no-write-lock-file
git diff --check
nix build .#nixosConfigurations.HOST.config.system.build.toplevel --no-link
```

Replace `HOST` with an active registry name. Newly created Nix files imported
by the flake must be added to Git's index before evaluation; inspect status
before staging. Builds do not activate the system.

## Remote access and deployment

SSH is restricted to the private Tailscale interface. After NixOS is installed,
enroll a host from its local console with `sudo tailscale up`, then verify
`ssh USER@HOST`. Do not
expose SSH or remote desktop directly to the internet.

Deploy a validated active host interactively:

```sh
./scripts/deploy-host.sh --host HOST
```

The helper validates the flake, builds on the target, and runs
`nixos-rebuild switch`. `switch` changes the running system. For another
remote account, pass `--target-user USER`.

## Add a host

Register the host once in `fleetHosts` in `flake.nix`, with a primary user and
host module whose `networking.hostName` matches its registry key. This creates
the normal NixOS output. Add
`diskDevice` only when a guarded `<host>-install` output is wanted; that output
uses the shared destructive Disko layout. Create the host directory and
`resume-offset.nix`, review hardware/storage overrides, then check and build the
new outputs before deployment. Update the current-host table in the root
README and the device table in `INSTALL.md`.
