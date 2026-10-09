# Infrastructure roadmap

This document is a revisit plan for the fleet's cloud backups, notifications,
fleet management, and optional hosted services. It is intentionally a plan,
not an instruction to create cloud resources immediately.

The laptops remain the source of truth for NixOS configuration. Cloud
resources should be managed separately with Terraform or OpenTofu, while Nix
continues to manage the NixOS hosts and local services.

## Current decisions

- NixOS and firmware updates remain manual for now.
- Clan and Colmena are being evaluated; neither is the required deployment
  mechanism yet.
- Secure Boot remains disabled and is out of scope.
- Syncthing's current firewall exposure is acceptable.
- Syncthing pairing and folders remain mutable and local.
- Power-management behavior must be checked before changing its configuration.
- Backblaze B2 is selected for Restic; the job remains disabled until the
  bucket, per-host credentials, and age recovery recipients are provisioned.
- Local notifications are sufficient initially; Zulip is optional.

## Decisions to make before provisioning

- [x] Select Backblaze B2 as the Restic object-storage provider.
- [ ] Create a private bucket and select its region/data-residency requirements.
- [ ] Estimate the initial and one-year backup size, including the per-host
      copies of `Shared` stored in separate repositories.
- [x] Set the backup policy to four runs per day; keep the latest four, six
      daily, eight weekly, and twelve monthly snapshots.
- [x] Include `/home/iindesa` on each host, including `Shared`; other
      accounts' homes and NixOS system state are excluded.
- [ ] Decide whether to use Zulip Cloud or self-host Zulip.
  - Recommendation: Zulip Cloud unless self-hosting is a deliberate goal.
- [ ] Select a domain and DNS provider if Zulip or other public services are
      needed.
- [ ] Decide whether notifications should begin with Healthchecks/local
      desktop notifications or go directly to Zulip.
- [ ] Choose Terraform or OpenTofu and pin its version/providers.

## Phase 1: infrastructure-as-code foundation

Do not apply cloud resources until the plan and state handling are reviewed.

- [ ] Create an `infra/` directory for Terraform/OpenTofu configuration.
- [ ] Add a reproducible development shell or package set containing the IaC
      tool, formatter, validation tools, and provider lock files.
- [ ] Configure remote state in a dedicated state bucket or managed backend.
- [ ] Keep infrastructure state separate from the Restic repository.
- [ ] Enable state locking where supported.
- [ ] Add `fmt`, `validate`, and plan checks to CI.
- [ ] Keep cloud credentials outside Git and outside committed `.tfvars` files.
- [ ] Establish a central secrets workflow for fleet and infrastructure,
      including inventory, access control, recovery, rotation, and audit.
- [ ] Decide how OpenTofu credentials fit into it: agenix, a password manager,
      or a cloud secret manager.
- [ ] Document the bootstrap procedure for the remote state backend.

Suggested layout:

```text
infra/
  README.md
  tofu/
    providers.tf
    versions.tf
    backend.tf
    storage.tf
    dns.tf
    zulip.tf
    tailscale.tf
```

Terraform/OpenTofu should manage cloud resources, DNS, firewalls, buckets, and
VMs. It should not replace the Nix flake as the source of truth for the laptop
operating systems.

## Phase 2: cloud Restic backups

Restic encrypts repository contents before upload. The storage provider should
not receive the repository password.

- [ ] Create a dedicated private B2 bucket and choose its region.
- [ ] Create a bucket- and per-host-prefix-restricted B2 application key for
      each host.
- [ ] Create a unique Restic password per host; encrypt each password and B2
      environment file to both the host recipient and an administrative
      recovery recipient.
- [x] Define one repository per host under `iindesa-fleet/<hostname>`; this
      isolates host credentials but stores replicated `Shared` data separately.
- [x] Add an optional `services.restic.backups.home` module, disabled until the
      bucket and encrypted host secrets are ready.
- [x] Back up `/home/iindesa`, including `Shared`; other account homes and
      system state are intentionally excluded.
- [x] Exclude cache, Trash, Snapper snapshots, and machine-local Syncthing
      configuration; see `docs/SECRETS.md`.
- [x] Configure persistent six-hour timers, automatic repository
      initialization, and `forget`/`prune` retention of the latest four, six
      daily, eight weekly, and twelve monthly snapshots.
- [x] Configure a monthly 5% repository data check and a local failure alert;
      these activate only with the backup module.
- [ ] Confirm the estimated B2 cost before enabling.
- [ ] Enable the job only after bucket, secrets, and recovery identity are
      configured; verify the first backup.
- [ ] Test a file restore on one host.
- [ ] Once Syncthing is idle and Restic backup/restore is verified, move the
      existing `@sync` mount from `/home/iindesa/Shared` to `/Shared`; update
      storage, Snapper, Syncthing, and Restic together without reformatting.
- [ ] Test a larger home-directory restore in a temporary location.
- [ ] Test recovery with a newly provisioned host.
- [ ] Record the restore procedure in the repository.

Do not enable B2 Object Lock or lifecycle deletion rules until Restic
maintenance and pruning have been tested. Immutable retention can prevent
expected deletion of old Restic pack files. If ransomware resistance is
required, use a separately designed append-only or immutable repository with
separate maintenance credentials.

## Phase 3: backup and host notifications

Start with the smallest useful notification system.

- [x] Configure a local `wall`/journal alert for failed Restic jobs; it is
      dormant while Restic remains disabled.
- [ ] Add a success heartbeat to Healthchecks.io or an equivalent service if a
      hosted heartbeat is acceptable.
- [ ] Alert on missed backup schedules rather than sending every successful
      backup as a message.
- [ ] Add local notifications for SMART failures and critical systemd failures.
- [ ] Decide whether firmware availability should generate a notification; do
      not automatically install firmware.
- [ ] If Zulip is selected, add a dedicated infrastructure stream.
- [ ] Store Zulip bot tokens or webhook credentials with agenix.
- [ ] Send only actionable events to Zulip to avoid notification noise.

Candidate events:

```text
backup failure
backup heartbeat missed
repository check failure
SMART warning
critical systemd failure
fleet deployment failure
host absent from Tailscale
```

## Phase 4: Zulip service

### Preferred path: managed Zulip

- [ ] Create a Zulip Cloud organization.
- [ ] Configure the organization, users, MFA, and retention policy.
- [ ] Create an infrastructure stream.
- [ ] Create a bot or webhook with minimum required permissions.
- [ ] Store the bot credential outside Git.
- [ ] Connect backup and deployment notifications.

### Alternative path: self-hosted Zulip

Only choose this path if operating Zulip is an explicit requirement.

- [ ] Provision a dedicated public VPS; do not host Zulip on a fleet laptop.
- [ ] Start with approximately 2 vCPU, 4 GB RAM, and 50–100 GB SSD.
- [ ] Use an officially supported guest OS and Zulip installation method.
- [ ] Manage the VPS, DNS, firewall, and volumes with Terraform/OpenTofu.
- [ ] Configure the guest using the official Zulip tooling rather than forcing
      the application into an unsupported NixOS module.
- [ ] Configure HTTPS, MFA, mail delivery, and account recovery.
- [ ] Back up the Zulip database and uploaded files off-machine.
- [ ] Test a complete restore before using it as the notification system.
- [ ] Define the upgrade and security-patch procedure.

## Phase 5: fleet management evaluation

Keep the existing manual deployment flow until a replacement is proven.

- [ ] Evaluate Clan for secrets, inventory, and host deployment needs.
- [ ] Evaluate Colmena for simple multi-host deployment and rollback.
- [ ] Compare both against the current flake and `scripts/deploy-host.sh`.
- [ ] Test the selected tool against `x1-9thgen` first.
- [ ] Verify remote sudo, build-host behavior, rollback, and hardware-file
      handling.
- [ ] Test deployment when the administration host and target have different
      Nix versions.
- [ ] Document the selected workflow.
- [ ] Deploy to the P50 only after the X1 workflow is reliable.

The update helper should remain available as a recovery path even after a
fleet manager is selected.

## Phase 6: Tailscale and DNS management

Only automate this after deciding whether the tailnet itself is managed by an
organization account.

- [ ] Decide whether Tailscale ACLs and device tags belong in IaC.
- [ ] If yes, manage ACL policy and tags with the Tailscale provider.
- [ ] Keep auth keys and OAuth credentials out of Terraform state where
      possible.
- [ ] Manage public DNS records through the selected DNS provider.
- [ ] Keep SSH limited to Tailscale as it is today.
- [ ] Do not expose fleet SSH or remote desktop directly to the Internet.

## Phase 7: build acceleration and optional services

Only add these if actual operational pain justifies them.

- [ ] Measure fleet build times.
- [ ] Add Cachix or another managed binary cache if repeated builds are slow.
- [ ] Consider a self-hosted Attic cache only if managing another service is
      justified.
- [ ] Consider Uptime Kuma, Prometheus, or Grafana only after lightweight
      heartbeat monitoring is insufficient.
- [ ] Keep monitoring infrastructure separate from the laptops.

## Completion criteria

This roadmap is complete enough for normal operation when:

- Restic backups run daily to an off-machine cloud repository.
- At least one file restore and one full test restore have succeeded.
- Backup failures produce a visible notification.
- Cloud credentials and repository passwords are not committed to Git.
- The selected fleet deployment tool can safely update and roll back the X1.
- Any hosted Zulip service has tested backups and a documented recovery path.
- The infrastructure state has a documented recovery/bootstrap procedure.
