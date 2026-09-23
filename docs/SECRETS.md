# Secrets and encrypted state

This flake includes the [agenix](https://github.com/ryantm/agenix) NixOS
module and installs the `agenix` command on every host. No encrypted secret
files are committed yet because the fleet does not have its age recipients or
backup destination defined.

## Create an age identity

Keep an administrative identity outside the repository:

```sh
mkdir -p ~/.config/age
age-keygen -o ~/.config/age/fleet-admin.txt
chmod 600 ~/.config/age/fleet-admin.txt
age-keygen -y ~/.config/age/fleet-admin.txt
```

The final command prints the public recipient. Use that recipient when creating
secrets. Additional recipients can be added for each host after installation;
use the host's SSH ed25519 public key with `agenix` only if that key is kept and
managed securely.

## Encrypt a secret

Create encrypted files outside the repository first, then move the resulting
`.age` file into `secrets/`:

```sh
agenix -i ~/.config/age/fleet-admin.txt -e secrets/restic-password.age
```

The `secrets/` directory is ignored by Git. Review recipients carefully and
never commit an unencrypted password, private key, Wi-Fi profile, or Syncthing
identity.

A NixOS module can consume a secret like this once the file exists:

```nix
age.secrets.restic-password = {
  file = ../secrets/restic-password.age;
  owner = primaryUser;
  group = "users";
  mode = "0400";
};
```

## SSH host identities

Every host generates a unique Ed25519 SSH host key on first boot through
`sshd-keygen.service`. This does not enable the SSH server. Inspect the public
host key with:

```sh
sudo cat /etc/ssh/ssh_host_ed25519_key.pub
sudo systemctl status sshd-keygen.service
```

These are host identity keys, not user login keys. User private keys should be
created and protected by the user rather than generated automatically in the
system configuration.

## Syncthing

Syncthing is already provisioned by `modules/common.nix`: the service runs as
the primary user, uses `/home/<user>/Shared` as its data directory, creates
`Shared/Desktop` and `Shared/Documents`, and opens its standard firewall
ports. Its identity
keys and `config.xml` are generated locally and must remain outside Git.

The first boot still requires pairing devices and selecting folders. That is
intentional: device IDs and folder topology are machine-specific. Agenix can
later be used for a centrally managed Syncthing configuration if reproducible
pairing is needed.

## Backups

Snapper now creates local hourly Btrfs snapshots for `/` and `/home`, with
conservative cleanup limits. Snapshots help recover from accidental changes but
are not backups: they live on the same encrypted disk and do not protect
against disk failure, theft, or loss of the machine. Inspect them with:

```sh
sudo snapper -c root list
sudo snapper -c home list
```

The `/.snapshots` and `/home/.snapshots` subvolumes are created automatically
by `snapper-init` on first boot.

Hibernation uses a 32 GiB swapfile inside the encrypted `@swap` Btrfs
subvolume. Its machine-specific `resume_offset` must be recorded in the host
configuration during provisioning. The X1 installer calculates and writes it
automatically. Manual P50 and T440s provisioning can use
`scripts/configure-btrfs-hibernation.sh`, which runs
`btrfs inspect-internal map-swapfile -r` and updates the host configuration.

For an off-machine backup, add a restic repository and an encrypted password
file before enabling a backup job. A future host or common module can then use
an arrangement like:

```nix
services.restic.backups.fleet = {
  repository = "sftp:backup.example:/srv/restic/fleet";
  passwordFile = config.age.secrets.restic-password.path;
  paths = [ "/home/${primaryUser}" ];
  exclude = [
    "/home/${primaryUser}/.cache"
    "/home/${primaryUser}/.config/syncthing"
  ];
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;
  };
};
```

Do not enable that example until the repository, SSH authentication, retention
policy, and restore procedure have been tested. A backup is only useful once a
restore has been verified.
