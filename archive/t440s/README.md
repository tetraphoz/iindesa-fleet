# Retired T440s host archive

The Lenovo ThinkPad T440s is no longer part of the active fleet. This
subdirectory preserves its last host-specific NixOS module and the local
`resume_offset` file for historical reference only.

These files are not flake outputs, are not imported by active hosts, and are
not a supported installation or deployment target. The archived configuration
was an unfinished migration plan for replacing the machine's former
LUKS/LVM/ext4 setup with encrypted Btrfs; it must not be applied to a machine
without a fresh inventory, verified hardware and storage configuration, and
explicit review.

The corresponding migration inventory is retained at
`inventories/t440s.tar.gz`. Inventory contents may expose hardware, network, or
user details; keep the archive private and inspect it before sharing.
