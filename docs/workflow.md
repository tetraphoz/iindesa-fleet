# Fleet administration workflow

The administration host is the source of truth for the fleet repository. Edit,
validate, commit, and push changes there, then deploy the resulting NixOS
configuration to the target machines over Tailscale and SSH.

```text
administration host
  edit -> validate -> commit -> push -> deploy over SSH

fleet hosts
  receive NixOS generations
  do not need GitHub credentials
```

## First-host bootstrap without SSH

If a host was installed before remote management was enabled, no SSH copy is
needed. The installer already placed the generated hardware file in the local
checkout at `/etc/nixos/fleet`.

From the host's local console, preserve that generated file, update the
checkout, restore the file, and activate the new configuration:

```sh
cd /etc/nixos/fleet
cp hosts/x1-9thgen/hardware-configuration.nix /tmp/x1-hardware-configuration.nix
git restore hosts/x1-9thgen/hardware-configuration.nix
git pull --ff-only origin main
cp /tmp/x1-hardware-configuration.nix \
  hosts/x1-9thgen/hardware-configuration.nix
sudo nixos-rebuild switch --flake /etc/nixos/fleet#x1-9thgen
```

Use the matching host name for the P50 or T440s. If the repository's GitHub
remote requires SSH credentials, inspect it with `git remote -v` and use the
HTTPS repository URL for this one-time pull, or transfer the updated checkout
with a USB drive. Do not use `git reset --hard` because it could erase the
machine-specific hardware file.

After the rebuild, enroll the host in Tailscale:

```sh
sudo tailscale up
```

Once it is enrolled, remote SSH and deployment can be used normally.

## Hardware configuration generated on a host

The X1 installer stores its generated hardware configuration in:

```text
/etc/nixos/fleet/hosts/x1-9thgen/hardware-configuration.nix
```

Copy it back to the administration checkout:

```sh
scp iindesa@x1-9thgen:/etc/nixos/fleet/hosts/x1-9thgen/hardware-configuration.nix \
  ./hosts/x1-9thgen/hardware-configuration.nix
```

Review the change before committing:

```sh
git diff -- hosts/x1-9thgen/hardware-configuration.nix
```

Check the LUKS device, EFI and `/boot` filesystems, Btrfs subvolumes,
`resumeDevice`, `resume_offset`, and swapfile configuration. Then commit it
from the administration host:

```sh
git add hosts/x1-9thgen/hardware-configuration.nix
git commit -m "Record X1 hardware configuration"
git push origin main
```

Use the equivalent host path for the P50 or T440s. Hardware configuration is
normally not secret, but do not commit passwords, private keys, Wi-Fi profiles,
or generated service credentials.

## Adding a package

Edit the administration checkout. Add packages needed by every host to:

```text
modules/common.nix
```

Add a package needed by only one host to its host configuration, for example:

```text
hosts/x1-9thgen/configuration.nix
```

Example:

```nix
environment.systemPackages = with pkgs; [
  htop
  neovim
  package-name
];
```

Search for the package first:

```sh
nix search nixpkgs package-name
```

Validate, commit, and push the change:

```sh
nix flake check --no-write-lock-file
nix build .#nixosConfigurations.x1-9thgen.config.system.build.toplevel --no-link
git diff --check

git add modules/common.nix
git commit -m "Add package-name to workstation environment"
git push origin main
```

Use the matching host configuration in the `git add` command when the package
is host-specific. Unfree packages may also need to be added to the allowlist
in the host configuration.

## Remote deployment

From the administration host and the fleet checkout:

```sh
nixos-rebuild switch \
  --flake .#x1-9thgen \
  --target-host iindesa@x1-9thgen \
  --use-remote-sudo
```

For the other machines:

```sh
nixos-rebuild switch \
  --flake .#p50 \
  --target-host iindesa@p50 \
  --use-remote-sudo

nixos-rebuild switch \
  --flake .#t440s \
  --target-host iindesa@t440s \
  --use-remote-sudo
```

Remote deployment copies the built NixOS closure to the target and activates
it. The target does not need to clone GitHub or have a GitHub token.

## Git and credential boundaries

Only the administration host needs GitHub credentials:

```sh
git remote -v
ssh -T git@github.com
```

The fleet hosts need SSH access from the administration host, but they do not
need personal GitHub accounts or GitHub private keys. Keep those credentials
on the administration host.

These are separate credentials and should not be copied between machines:

- Tailscale authentication.
- SSH access to the fleet hosts.
- GitHub access.
- LUKS unlock passphrases.
- `iindesa` login passwords.

## Routine update sequence

A normal change should follow this sequence:

```sh
cd /path/to/iindesa-fleet

git pull --ff-only origin main
# edit the relevant Nix files

nix flake check --no-write-lock-file
nix build .#nixosConfigurations.HOST.config.system.build.toplevel --no-link
git diff --check

git add PATHS

git commit -m "Describe the fleet change"
git push origin main

nixos-rebuild switch \
  --flake .#HOST \
  --target-host iindesa@HOST \
  --use-remote-sudo
```

Replace `HOST` with `x1-9thgen`, `p50`, or `t440s`.
