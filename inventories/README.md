# Migration inventories

The compressed archives in this directory are migration inputs for the fleet
configurations. They contain hardware and system observations, not a NixOS
configuration.

The X1 Carbon 9th Gen does not have an inventory yet. After booting that
machine, collect one from the repository root with:

```sh
sudo ./nixos-inventory.sh x1-9thgen inventories
```

The command creates both `inventories/x1-9thgen/` and its compressed archive.
For another machine, replace the host name and output directory as needed:

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
