# Secrets and encrypted state

This flake includes the [agenix](https://github.com/ryantm/agenix) NixOS
module and installs the `agenix` command on every host. Backblaze B2 is the
Restic target. X1 uses the `x1-9thgen` bucket and dedicated age identity
`/var/lib/agenix/x1-host.txt`. Its Restic password and B2 credentials are
encrypted under `secrets/restic/`; the OpenClaw gateway token is encrypted
under `secrets/openclaw/`. The initial agenix activation failed, but the
corrected identity allowed Restic to initialize its repository; the user
reports that the first backup completed. A restore test was explicitly waived,
so recovery has not been verified. The X1 B2 key is restricted to its bucket
but has no object-prefix restriction. P50 remains disabled; do not describe the
X1 backup as recovery-verified until a restore test succeeds.

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
recipients may be committed, but never the private identity. Encrypt each
host's secrets to the admin recipient and the recipient of that host's
configured agenix identity. X1 uses the dedicated identity documented below;
other hosts may use their SSH Ed25519 host key. Keep the admin private identity
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
outside the repository, with an independent recovery copy. A host recipient
is usable only when the corresponding private identity is present at the path
configured for agenix on that host.

## Host age identities

Every host generates a unique Ed25519 SSH host key on first boot through
`sshd-keygen.service`. This does not enable the SSH server. Inspect it with:

```sh
sudo cat /etc/ssh/ssh_host_ed25519_key.pub
sudo systemctl status sshd-keygen.service
```

X1 uses a separate age identity at `/var/lib/agenix/x1-host.txt`, selected by
`age.identityPaths` in its host configuration. Keep that file root-owned with
mode `0400`; never copy it into the repository or chat. Its public recipient
may be shared and used to encrypt X1 secrets. The admin recovery recipient
allows recovery without that host identity. Other hosts may use the default
SSH Ed25519 host-key identity. User login keys are separate and should be
created and protected by the user.

## OpenClaw gateway

X1 uses `nix-openclaw`'s exported NixOS `openclaw-gateway` module. On
2026-10-16, the system was switched from v2026.9.5 to v2026.10.4 (commit
`08732c0d9fbfc34e7c285cdbac8130bacaaad9db`). The new package's config validates,
but its first startup rejected the existing main agent database at schema 21
and requested a session-identity migration. `OPENCLAW_NIX_MODE=1` prevents
`doctor --fix` from running against the Nix-managed config. As session history
was disposable, the gateway was stopped and the old `openclaw-agent.sqlite*`
files moved to a private backup under `/home/iindesa/.openclaw/backups/`. The
gateway was restarted on 2026-10-16 and created a fresh agent database; a
follow-up check showed it active with no restarts. The service runs as
`iindesa`, stores runtime state under
`/home/iindesa/.openclaw`, and binds to loopback. Its gateway token is provided
at runtime through the age-encrypted systemd environment file
`secrets/openclaw/x1-gateway.env.age`; the Nix-managed config contains only an
environment SecretRef, not the token value. OpenAI ChatGPT/Codex subscription
auth is enrolled (OAuth provider `openai`), with `openai/gpt-6-astra` as the
Nix-managed primary. No explicit `agents.defaults.subagents.model` is set. The
OAuth profile lives in OpenClaw runtime state under the configured
home-directory Restic backup scope; the first backup was reported complete,
but recovery remains
unverified until a restore test succeeds. No messaging channel is configured.
The X1 host explicitly permits this package despite Nixpkgs' prompt-injection
risk warning; keep the gateway loopback-only and review the exception when
updating OpenClaw.

To enroll or re-enroll OpenAI OAuth, run the installed command from an
interactive terminal as `iindesa`:

```sh
enroll-openclaw-openai
```

Use `enroll-openclaw-openai --device-code` if the browser callback is
unavailable. The script uses the Nix-managed config and OpenClaw state, reads
the age-decrypted gateway environment file without printing it, and does not
modify the declared model config or use an API key. It lists the saved OpenAI
auth profiles and models visible to the signed-in account. Astra is not enabled
for every account. The script is also available at
`scripts/enroll-openclaw-openai.sh` for reuse on other hosts; set its documented
environment overrides if a host uses different config, state, or secret-file
paths.

### Resetting an incompatible agent database

Use this only when session history is intentionally disposable. Prefer a
supported migration or restore when sessions must be preserved. If startup
reports an incompatible `openclaw-agent.sqlite` schema and recommends
`doctor --fix`, note that `OPENCLAW_NIX_MODE=1` protects the Nix-managed config
and blocks that repair command. Do not bypass the guard against
`/etc/openclaw/openclaw.json`.

With the gateway stopped, run the following as `iindesa`. It moves the agent
database and related SQLite files (including any WAL/SHM sidecars) aside; it
does not delete them. The next gateway start creates a fresh database. Keep the
backup private and outside Git.

```sh
sudo systemctl stop openclaw-gateway.service
systemctl is-active openclaw-gateway.service  # expect: inactive

state="$HOME/.openclaw"
agent="$state/agents/main/agent"
test -f "$agent/openclaw-agent.sqlite" || exit 1
umask 077
mkdir -p "$state/backups"
backup="$state/backups/agent-db-fresh-start-$(date +%Y%m%d-%H%M%S)"
mkdir -m 0700 "$backup"
for file in "$agent"/openclaw-agent.sqlite*; do
  [ -e "$file" ] || continue
  mv -- "$file" "$backup/"
done
ls -l "$backup"

sudo systemctl start openclaw-gateway.service
systemctl status openclaw-gateway.service --no-pager
sudo journalctl -u openclaw-gateway.service -n 80 --no-pager
```

Check that the service stays active and the schema-version error is gone before
considering the reset complete. Old browser session IDs will no longer resolve;
open a new session in the Control UI. A `token_mismatch` message is separate from
the database reset: update the Control UI's saved token using the current
Dashboard settings, without sharing the token. This intentionally abandons data
in the archived agent database. Only files matching `openclaw-agent.sqlite*`
are moved; the procedure does not intentionally change the Nix config, gateway
environment file, or other state files. Verify login and session behavior after
startup. Do not restore the archived database over a newly created one without
a deliberate recovery plan.

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
`b2:<bucket>:iindesa-fleet/<hostname>` and a separate Restic password. The X1
uses the dedicated `x1-9thgen` bucket and a bucket-restricted B2 application
key; that key does not have an object-prefix restriction. Keep buckets
host-specific if using bucket-only keys; for a shared bucket, restrict each
key to its exact host prefix. Identical `Shared` contents stored in separate
host repositories count separately toward B2 storage. The schedule is every
six hours with up to 30 minutes of jitter. Retention keeps the latest four
snapshots (about one day), one snapshot per day for six days, eight weekly,
and twelve monthly. `keep-daily = 6` is a retention window, not the backup
frequency. The laptop must be awake and online for each run; the persistent
timer catches up once after downtime rather than creating snapshots for every
missed interval. Review expected B2 storage cost, bucket privacy, and region;
these were requested but are not confirmed here. A monthly integrity check
reads a 5% data sample; it does not replace a periodic restore test.

The X1's encrypted files are present. For each additional host, create these
after its age recipient is available:

- `secrets/restic/<hostname>-password.age` — a unique, strong Restic
  repository password.
- `secrets/restic/<hostname>-b2.env.age` — a B2 application key in systemd
  EnvironmentFile format: `B2_ACCOUNT_ID` contains the application-key ID and
  `B2_ACCOUNT_KEY` contains its application key (not the account master key).

Restrict each B2 key to its dedicated private bucket and, where a bucket is
shared, an exact host prefix such as `iindesa-fleet/p50/`. The X1 key is
currently bucket-only. Keys need the permissions required for Restic backup,
pruning, and checking; do not apply B2 lifecycle deletion rules or Object Lock
until Restic maintenance has been tested. Keep an administrative recovery
recipient on each encrypted file so a lost host does not make its repository
password unrecoverable.

The X1 host config opts into `fleet.backups.restic` with bucket name
`x1-9thgen`; other hosts remain disabled. Once activated, the module schedules
backups every six hours with persistent systemd timers, initializes the
repository on first successful use, prunes old snapshots, and runs a monthly
sample check. A failure is written to the journal and broadcast to logged-in
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

The X1 Restic repository is initialized and the user reports that the first
backup completed. The user waived a restore test; recovery remains
unverified, and the backup must not be described as recovery-ready until a
restore succeeds. B2 privacy, region, and expected-cost review remain
unconfirmed. Other hosts still need their own buckets or an explicitly
shared-bucket design and per-host credentials. To verify recovery later, test
on a separate device or clean installation before restoring over a live home.
