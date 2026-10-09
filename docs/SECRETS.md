# Secrets and encrypted state

This flake includes the [agenix](https://github.com/ryantm/agenix) NixOS
module and installs the `agenix` command on every host. Backblaze B2 has been
selected for Restic, but backups remain disabled until a private bucket,
per-host credentials, and recovery-capable age recipients are provisioned. No
secret files or cloud credentials have been created.

## Create an age identity

Keep an administrative identity outside the repository:

```sh
mkdir -p ~/.config/age
age-keygen -o ~/.config/age/fleet-admin.txt
chmod 600 ~/.config/age/fleet-admin.txt
age-keygen -y ~/.config/age/fleet-admin.txt
```

The final command prints the public recipient. Add public recipients to the
repository's `secrets.nix` recipient map when it is established; public
recipients may be committed, but never the private identity. Include the admin
recipient and, once available, each host's SSH Ed25519 public-key recipient
when encrypting that host's secrets. Keep the admin private identity
independently recoverable and outside the fleet devices.

## Encrypt a secret

Create encrypted files outside the repository first, then place the resulting
`.age` ciphertext under `secrets/`. Review recipients carefully. Only encrypted
`.age` files under `secrets/` are allowed by `.gitignore`; plaintext passwords,
private keys, Wi-Fi profiles, and Syncthing identities remain ignored and must
never be committed. The encrypted files must be tracked with the flake so
NixOS can build the agenix secret declarations.

For backup secrets, encrypt each host's Restic password and B2 application-key
environment file to **both** that host's age recipient and the administrative
recovery recipient. Keep the admin identity offline or otherwise protected
outside the repository, with an independent recovery copy. Host recipients are not available for an active host until its NixOS host
key has been created.

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
the primary user, currently uses `/home/<user>/Shared` as its data directory,
creates `Shared/Desktop` and `Shared/Documents`, and opens its standard
firewall ports. Its identity keys and `config.xml` are generated locally and
must remain outside Git. A move to `/Shared` is planned only after current
sync activity and a verified Restic backup/restore; see `docs/OPERATIONS.md`.

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
configuration during provisioning. The universal guarded installer calculates
and writes the selected host's offset automatically. P50 maintenance can use
`scripts/configure-btrfs-hibernation.sh`, which requires the root and `/swap`
subvolume to be exact Btrfs mount points, runs
`btrfs inspect-internal map-swapfile -r`, and updates the dedicated host
module. For example, with the P50 filesystems mounted under `/mnt`:

```sh
sudo ./scripts/configure-btrfs-hibernation.sh \\
  --root /mnt \\
  --config hosts/p50/resume-offset.nix
```

### Backblaze B2 Restic backups

`modules/restic-backup.nix` defines the B2 workflow, but it is **disabled by
default**. In the current layout it backs up the primary user's
`/home/iindesa` directory on each host, including `/home/iindesa/Shared`. Other
accounts' home directories are not included. After the planned move to `/Shared`,
the backup paths and snapshot exclusions must be updated together so Restic
continues to cover shared data. System closures, `/nix`, and system
configuration are intentionally not backed up. Cache, Trash, Snapper snapshot
directories, and machine-local Syncthing configuration are excluded. Restic
encrypts repository contents before upload.

Each host has a separate repository under
`b2:<bucket>:iindesa-fleet/<hostname>`, a separate Restic password, and a
bucket/prefix-restricted B2 application key. This limits the effect of a
compromised host, but it means identical `Shared` contents are stored in each
host's repository and count toward B2 storage. The planned schedule is every
six hours with up to 30 minutes of jitter. Retention keeps the latest four
snapshots (about one day), one snapshot per day for six days, eight weekly,
and twelve monthly. `keep-daily = 6` is a retention window, not the backup
frequency. The laptop must be awake and online for each run; the persistent
timer catches up once after downtime rather than creating snapshots for every
missed interval. Confirm expected B2 storage cost before enabling. A monthly
integrity check reads a 5% data sample; it does not replace a periodic restore
test.

For each host, create these encrypted files after its age recipient is
available:

- `secrets/restic/<hostname>-password.age` — a unique, strong Restic
  repository password.
- `secrets/restic/<hostname>-b2.env.age` — a B2 application key in systemd
  EnvironmentFile format: `B2_ACCOUNT_ID` contains the application-key ID and
  `B2_ACCOUNT_KEY` contains its application key (not the account master key).

Restrict each B2 key to the dedicated private bucket and an exact host prefix,
for example `iindesa-fleet/p50/`. It needs the permissions required for Restic
backup, pruning, and checking; do not apply B2 lifecycle deletion rules or
Object Lock until the Restic maintenance behavior has been tested. Keep an
administrative recovery recipient on each encrypted file so a lost host does
not make its repository password unrecoverable.

After creating the bucket and all required host secrets, configure
`fleet.backups.restic.enable = true;` and the bucket name in the common module
(or enable individual hosts as their recipients become available). The module
then schedules backups every six hours with persistent systemd timers,
initializes the repository on first successful use, prunes old snapshots, and
runs a monthly sample check. A failure is written to the journal and broadcast to logged-in
terminals with `wall`.

Useful host commands after activation:

```sh
sudo systemctl status restic-backups-home.timer restic-home-check.timer
sudo journalctl -u restic-backups-home.service -u restic-home-check.service
sudo restic-home snapshots
sudo restic-home check
```

Test recovery by restoring a selected snapshot to a temporary directory first;
review the files and permissions before copying anything back into a live home:

```sh
sudo restic-home restore latest --target /tmp/restic-restore-test
```

For a lost host, use the administrative age identity to decrypt that host's
B2 environment and Restic password into protected temporary files on the
recovery machine, then connect to
`b2:<bucket>:iindesa-fleet/<hostname>` and restore to a temporary target. Remove
the decrypted credential files after the recovery test. Do not restore directly
over a live `/home` until contents and permissions have been reviewed.

The bucket name, B2 keys, Restic passwords, and recipient setup are still
pending. Do not rely on the service until a first backup has completed and a
restore test has been verified on a separate device or clean installation.
