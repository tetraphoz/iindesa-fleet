# Migration inventories

The compressed archives in this directory are historical migration inputs.
They contain hardware and system observations, not NixOS configurations, and
may contain sensitive machine details. The T440s inventory is retained only
for the retired host's archive; it is not evidence that the machine is still
in the active fleet.

For a new active host, collect an inventory from the repository root with:

```sh
sudo ./nixos-inventory.sh x1-9thgen inventories
```

The command creates both `inventories/x1-9thgen/` and its compressed archive.
For another authorized active machine, replace the host name and output
directory as needed:

```sh
sudo ./nixos-inventory.sh HOST inventories
# Replace an existing collection deliberately:
sudo ./nixos-inventory.sh --force HOST inventories
```

Use `--no-archive` to skip the archive and `--help` for all options. Review
`logs/sensitive-file-review.txt` before committing newly collected inventory
data. The collector intentionally avoids copying common secret files, but its
output still contains potentially sensitive hardware, network, user, and
configuration information and must be reviewed before sharing.
