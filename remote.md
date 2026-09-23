# Remote management

The fleet enables SSH and Tailscale for remote administration. SSH is allowed
through the private `tailscale0` interface only; it is not opened on the
normal LAN or Wi-Fi interfaces.

## Enroll a host

Apply the host configuration locally first, then authenticate Tailscale:

```sh
sudo nixos-rebuild switch --flake /etc/nixos/fleet#x1-9thgen
sudo tailscale up
```

Use the matching flake name on the P50 or T440s. Complete the authentication
in the URL printed by `tailscale up`. Repeat this once per host. MagicDNS names
or the Tailscale IP addresses can then be used from the administration host:

```sh
ssh iindesa@x1-9thgen
ssh iindesa@p50
ssh iindesa@t440s
```

The initial configuration permits password authentication only over the
private Tailscale network. Root SSH login is disabled. The `iindesa` account
uses `sudo` for administration.

## Remote NixOS rebuilds

From the administration host and the fleet checkout:

```sh
nixos-rebuild switch \
  --flake .#x1-9thgen \
  --target-host iindesa@x1-9thgen \
  --use-remote-sudo
```

Replace the host name for the other machines. Use an SSH key for routine
administration. After the key has been installed and tested, change
`PasswordAuthentication` to `false` in `modules/common.nix` and rebuild all
hosts.

## Basic fleet checks

```sh
for host in x1-9thgen p50 t440s; do
  ssh "iindesa@$host" 'hostname; systemctl --failed --no-legend'
done
```

Do not expose port 22 or a graphical remote-desktop service directly to the
internet. RDP is optional for occasional desktop control, but SSH over
Tailscale is the primary management path. If graphical access is needed, use a
VPN-only tool such as RustDesk or NoMachine rather than public RDP.
