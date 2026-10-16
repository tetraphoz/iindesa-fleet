# Infrastructure roadmap

This document tracks fleet-specific cloud backups, notifications, fleet
management, and integration with optional hosted services. It is intentionally
a plan, not an instruction to create cloud resources immediately.

The laptops remain the source of truth for NixOS configuration. Public VPS
resources and hosted applications are managed separately in the `iindesa-infra`
project; Nix continues to manage the fleet hosts and their local services.

## Current decisions

- NixOS and firmware updates remain manual for now.
- Clan and Colmena are being evaluated; neither is the required deployment
  mechanism yet.
- Secure Boot remains disabled and is out of scope.
- Syncthing's current firewall exposure is acceptable.
- Syncthing pairing and folders remain mutable and local.
- Power-management behavior must be checked before changing its configuration.
- Backblaze B2 is selected for Restic. X1 uses its `x1-9thgen` bucket and
  dedicated age identity. The repository is initialized, and the user reports
  the first backup completed. A restore test was explicitly waived, so recovery
  remains unverified. P50 remains disabled.
- Self-hosted Zulip and Vikunja are planned for the separate VPS project. Using
  Zulip as the fleet's notification destination remains optional until the
  service and integration are configured and tested.

## Decisions to make before provisioning

- [x] Select Backblaze B2 as the Restic object-storage provider.
- [ ] Confirm privacy, region, and data-residency settings for X1's existing
      `x1-9thgen` bucket; create buckets for other hosts if needed.
- [ ] Estimate the initial and one-year backup size, including the per-host
      copies of `Shared` stored in separate repositories.
- [x] Set the backup policy to four runs per day; keep the latest four, six
      daily, eight weekly, and twelve monthly snapshots.
- [x] Include `/home/iindesa` on each host, including `Shared`; other
      accounts' homes and NixOS system state are excluded.
- [x] Choose self-hosted Zulip and Vikunja as the intended first VPS
      applications; their provisioning and operations are tracked in
      `iindesa-infra`.
- [ ] Select a domain and DNS provider for the public services in
      `iindesa-infra`.
- [ ] Decide whether fleet notifications should begin with Healthchecks/local
      desktop notifications or go directly to Zulip.

## Phase 1: separate VPS infrastructure

The independent `iindesa-infra` project now owns the Hetzner/OpenTofu scaffold
and the planned NixOS VPS for Zulip and Vikunja. Follow that project's README
and decisions document for provider authentication, SOPS/age secrets, state
backend, provisioning, and service operations. Do not recreate an `infra/`
configuration in this fleet repository or apply cloud resources before the
separate project's state and recovery plan are ready.

## Phase 2: cloud Restic backups

Restic encrypts repository contents before upload. The storage provider should
not receive the repository password. Keep the fleet's backup policy and host
configuration here; if cloud storage resources are provisioned through
`iindesa-infra`, keep their state backend separate from the Restic repositories.

- [ ] Confirm X1's bucket privacy and region; create dedicated buckets for
      other hosts if needed.
- [x] Restrict X1's B2 key to its dedicated bucket; it has no object-prefix
      restriction. For any shared bucket, restrict each host key to its exact
      repository prefix.
- [x] Create a unique X1 Restic password and B2 environment file encrypted to
      both the host and administrative recovery recipients.
- [ ] Prepare equivalent credentials and encrypted files for additional hosts.
- [x] Define one repository per host under `iindesa-fleet/<hostname>`; this
      isolates host credentials but stores replicated `Shared` data separately.
- [x] Add the optional `services.restic.backups.home` module; it is disabled
      by default and enabled on X1 with its bucket and encrypted host secrets.
- [x] Back up `/home/iindesa`, including `Shared`; other account homes and
      system state are intentionally excluded.
- [x] Exclude cache, Trash, Snapper snapshots, and machine-local Syncthing
      configuration; see `docs/SECRETS.md`.
- [x] Configure persistent six-hour timers, automatic repository
      initialization, and `forget`/`prune` retention of the latest four, six
      daily, eight weekly, and twelve monthly snapshots.
- [x] Configure a monthly 5% repository data check and a local failure alert;
      these activate only with the backup module.
- [ ] Review the expected B2 cost; the estimate has not been confirmed here.
- [x] Deploy the configured X1 job; the user reports that its first backup
      completed.
- [ ] Test a file restore to a temporary target before treating the repository
      as recovery-ready. The user waived this test for the initial X1 setup, so
      recovery remains unverified.
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
      active on X1 and dormant on hosts where Restic remains disabled.
- [ ] Add a success heartbeat to Healthchecks.io or an equivalent service if a
      hosted heartbeat is acceptable.
- [ ] Alert on missed backup schedules rather than sending every successful
      backup as a message.
- [ ] Add local notifications for SMART failures and critical systemd failures.
- [ ] Decide whether firmware availability should generate a notification; do
      not automatically install firmware.
- [ ] Decide whether Zulip should be used as the fleet alert sink; see
      Phase 4 for the service-integration checklist.

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

## Phase 4: hosted-service integration

Self-hosted Zulip and Vikunja are the intended VPS applications; their
installation, public access, backups, and upgrade procedures are tracked in
`iindesa-infra`. This fleet roadmap covers only whether and how fleet events
should be sent to Zulip.

- [ ] Decide whether to route fleet notifications to Zulip or continue with
      local/Healthchecks notifications.
- [ ] If selected, create a dedicated infrastructure stream and a bot/webhook
      with minimum required permissions.
- [ ] Store bot credentials through the approved encrypted secret workflow.
- [ ] Send only actionable events and test delivery and credential rotation.

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
- [ ] Manage public DNS records for hosted applications through the provider
      selected in `iindesa-infra`.
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

- Restic backups run at the configured cadence to an off-machine cloud
  repository.
- At least one file restore and one full test restore have succeeded.
- Backup failures produce a visible notification.
- Plaintext cloud credentials and repository passwords are not committed to
  Git; encrypted infrastructure secrets follow the separate
  `iindesa-infra` SOPS/age policy.
- The selected fleet deployment tool can safely update and roll back the X1.
- Any hosted Zulip service has tested backups and a documented recovery path.
- The infrastructure state has a documented recovery/bootstrap procedure.
