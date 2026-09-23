#!/usr/bin/env bash
#
# nixos-inventory.sh
#
# Cross-distro Linux -> NixOS migration inventory collector.
#
# Supported families:
#   - Debian / Ubuntu
#   - Arch Linux
#   - Fedora / RHEL / Rocky / Alma / CentOS
#   - openSUSE / SUSE
#   - Alpine
#
# Usage:
#   sudo ./nixos-inventory.sh
#   sudo ./nixos-inventory.sh server01 /path/to/inventories
#   sudo ./nixos-inventory.sh --host server01 --output /path/to/inventories
#   sudo ./nixos-inventory.sh --force server01
#
# Output:
#   inventories/
#     server01/
#       metadata/
#       hardware/
#       storage/
#       network/
#       packages/
#       services/
#       users/
#       configuration/
#       logs/
#
# The script intentionally does NOT copy:
#   - /etc/shadow
#   - private SSH keys
#   - TLS private keys
#   - .env files
#   - passwords
#   - API tokens
#   - cloud credentials
#   - NetworkManager connection secrets
#

# Most collect_shell snippets are intentionally single-quoted: they must be
# expanded by the subshell when collected, not by this script.
# shellcheck disable=SC2016

set -u
set -o pipefail

############################################
# Configuration
############################################

usage() {
    cat <<'EOF'
Usage: nixos-inventory.sh [OPTIONS] [HOST [OUTPUT_DIR]]

Collect a migration inventory from the current Linux machine.

Arguments:
  HOST                 Inventory name (default: short hostname)
  OUTPUT_DIR           Parent directory (default: ./inventories)

Options:
  --host NAME          Set the inventory name
  --output DIRECTORY   Set the parent output directory
  --force              Replace an existing inventory directory
  --no-archive         Do not create the .tar.gz archive
  -h, --help           Show this help

Run as root for the most complete hardware, storage, service, and user data.
The collector intentionally excludes common secret files, but review the
result before committing or sharing it.
EOF
}

HOST_NAME=''
BASE_DIR='./inventories'
FORCE=0
CREATE_ARCHIVE=1
POSITIONAL=()

while (($# > 0)); do
    case "$1" in
        --host)
            (($# >= 2)) || { echo "ERROR: --host requires a value" >&2; exit 1; }
            HOST_NAME=$2
            shift 2
            ;;
        --output)
            (($# >= 2)) || { echo "ERROR: --output requires a directory" >&2; exit 1; }
            BASE_DIR=$2
            shift 2
            ;;
        --force)
            FORCE=1
            shift
            ;;
        --no-archive)
            CREATE_ARCHIVE=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            POSITIONAL+=("$@")
            break
            ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            echo "       Use --help for usage." >&2
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if ((${#POSITIONAL[@]} > 2)); then
    echo "ERROR: Too many positional arguments." >&2
    echo "       Use --help for usage." >&2
    exit 1
fi

if ((${#POSITIONAL[@]} >= 1)); then
    [[ -z "$HOST_NAME" ]] || {
        echo "ERROR: host specified both positionally and with --host." >&2
        exit 1
    }
    HOST_NAME=${POSITIONAL[0]}
fi
if ((${#POSITIONAL[@]} == 2)); then
    [[ "$BASE_DIR" == './inventories' ]] || {
        echo "ERROR: output directory specified both positionally and with --output." >&2
        exit 1
    }
    BASE_DIR=${POSITIONAL[1]}
fi

HOST_NAME=${HOST_NAME:-$(hostname -s)}

# Host names become directory names below BASE_DIR.  Reject rather than
# silently rewrite invalid input, especially path traversal such as '..'.
if [[ ! "$HOST_NAME" =~ ^[[:alnum:]_.-]+$ || "$HOST_NAME" == "." || "$HOST_NAME" == ".." ]]; then
    echo "ERROR: Invalid hostname: $HOST_NAME" >&2
    echo "       Use only letters, digits, '.', '_' and '-'" >&2
    exit 1
fi

OUT="${BASE_DIR}/${HOST_NAME}"

############################################
# Colors
############################################

if [[ -t 1 ]]; then
    BOLD="$(printf '\033[1m')"
    GREEN="$(printf '\033[32m')"
    YELLOW="$(printf '\033[33m')"
    RED="$(printf '\033[31m')"
    RESET="$(printf '\033[0m')"
else
    BOLD=""
    GREEN=""
    YELLOW=""
    RED=""
    RESET=""
fi

############################################
# Helpers
############################################

log() {
    printf '%b[%s]%b %s\n' "$GREEN" "*" "$RESET" "$*"
}

warn() {
    printf '%b[WARNING]%b %s\n' "$YELLOW" "$RESET" "$*" >&2
}

error() {
    printf '%b[ERROR]%b %s\n' "$RED" "$RESET" "$*" >&2
}

if [[ -L "$OUT" ]]; then
    error "Output path must not be a symbolic link: $OUT"
    exit 1
fi
if [[ -e "$OUT" && ! -d "$OUT" ]]; then
    error "Output path exists and is not a directory: $OUT"
    error "Move or remove it before collecting this inventory."
    exit 1
fi
if [[ -d "$OUT" ]]; then
    if ((FORCE == 0)); then
        error "Inventory already exists: $OUT"
        error "Use --force to replace it, or choose another host/output directory."
        exit 1
    fi
    rm -rf -- "$OUT" || {
        error "Unable to remove existing inventory: $OUT"
        exit 1
    }
fi

if [[ $EUID -ne 0 ]]; then
    warn "Not running as root; some hardware, storage, service, and user data may be incomplete."
fi

if ! mkdir -p \
    "$OUT/metadata" \
    "$OUT/hardware" \
    "$OUT/storage" \
    "$OUT/network" \
    "$OUT/packages" \
    "$OUT/services" \
    "$OUT/users" \
    "$OUT/configuration" \
    "$OUT/logs"; then
    error "Unable to create inventory directory: $OUT"
    exit 1
fi

############################################
# Command runner
############################################

collect() {
    local file="$1"
    shift

    local output="$OUT/$file"

    mkdir -p "$(dirname "$output")"

    {
        printf '# Generated: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
        printf '# Command:'

        printf ' %q' "$@"
        printf '\n\n'

        "$@"
    } > "$output" 2>&1 || true
}

collect_shell() {
    local file="$1"
    local command="$2"

    local output="$OUT/$file"

    mkdir -p "$(dirname "$output")"

    {
        printf '# Generated: %s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
        printf '# Command: %s\n\n' "$command"

        bash -c "$command"
    } > "$output" 2>&1 || true
}

############################################
# Detect OS
############################################

log "Detecting operating system..."

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
else
    ID="unknown"
    PRETTY_NAME="Unknown Linux"
fi

DISTRO_ID="${ID:-unknown}"
DISTRO_NAME="${PRETTY_NAME:-$DISTRO_ID}"
DISTRO_VERSION="${VERSION_ID:-unknown}"

case "$DISTRO_ID" in
    ubuntu|debian|linuxmint|pop)
        DISTRO_FAMILY="debian"
        ;;

    arch|manjaro|endeavouros)
        DISTRO_FAMILY="arch"
        ;;

    fedora|rhel|rocky|almalinux|centos)
        DISTRO_FAMILY="rpm"
        ;;

    opensuse*|sles|suse)
        DISTRO_FAMILY="suse"
        ;;

    alpine)
        DISTRO_FAMILY="alpine"
        ;;

    *)
        DISTRO_FAMILY="unknown"
        ;;
esac

############################################
# Metadata
############################################

log "Collecting metadata..."

collect_shell metadata/os-release \
    'cat /etc/os-release'

collect_shell metadata/kernel \
    'uname -a'

collect_shell metadata/kernel-version \
    'uname -r'

collect_shell metadata/architecture \
    'uname -m'

collect_shell metadata/hostname \
    'hostnamectl 2>/dev/null || hostname'

collect_shell metadata/uptime \
    'uptime'

collect_shell metadata/boot-mode \
    'if [ -d /sys/firmware/efi ]; then echo UEFI; else echo BIOS/Legacy; fi'

collect_shell metadata/virtualization \
    'systemd-detect-virt 2>/dev/null || true'

collect_shell metadata/init-system \
    'ps -p 1 -o comm='

collect_shell metadata/timezone \
    'timedatectl 2>/dev/null || cat /etc/timezone 2>/dev/null || true'

collect_shell metadata/locale \
    'locale 2>/dev/null || true'

# Hash machine-id rather than recording it directly.
collect_shell metadata/machine-id-hash \
    'if [ -r /etc/machine-id ]; then
        sha256sum /etc/machine-id
    fi'

cat > "$OUT/metadata/inventory.conf" <<EOF
HOST_NAME=$HOST_NAME
DISTRO_ID=$DISTRO_ID
DISTRO_FAMILY=$DISTRO_FAMILY
DISTRO_VERSION=$DISTRO_VERSION
DISTRO_NAME=$DISTRO_NAME
COLLECTED_AT=$(date --iso-8601=seconds 2>/dev/null || date)
EOF

############################################
# Hardware
############################################

log "Collecting hardware..."

collect hardware/cpu \
    lscpu

collect hardware/memory \
    free -h

collect hardware/pci \
    lspci -nnk

collect hardware/usb \
    lsusb

collect hardware/block-devices \
    lsblk -e7 -o NAME,KNAME,TYPE,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS,MODEL

collect_shell hardware/gpu \
    'lspci -nnk | grep -EA4 "VGA|3D|Display" || true'

collect hardware/kernel-modules \
    lsmod

collect_shell hardware/dmi \
    'if command -v dmidecode >/dev/null 2>&1; then
        dmidecode
    else
        echo "dmidecode not installed"
    fi'

collect_shell hardware/cpu-info \
    'cat /proc/cpuinfo'

collect_shell hardware/memory-info \
    'cat /proc/meminfo'

collect_shell hardware/firmware \
    'if command -v fwupdmgr >/dev/null 2>&1; then
        fwupdmgr get-devices
    else
        echo "fwupdmgr not installed"
    fi'

############################################
# Storage
############################################

log "Collecting storage configuration..."

collect storage/df \
    df -hT

collect storage/mounts \
    findmnt -A

collect storage/fstab \
    cat /etc/fstab

collect storage/crypttab \
    cat /etc/crypttab

collect storage/swaps \
    swapon --show

collect storage/mdstat \
    cat /proc/mdstat

collect_shell storage/mdadm \
    'if command -v mdadm >/dev/null 2>&1; then
        mdadm --detail --scan
    fi'

collect_shell storage/lvm \
    'if command -v pvs >/dev/null 2>&1; then
        echo "=== Physical Volumes ==="
        pvs
        echo
        echo "=== Volume Groups ==="
        vgs
        echo
        echo "=== Logical Volumes ==="
        lvs
    fi'

collect_shell storage/zfs \
    'if command -v zpool >/dev/null 2>&1; then
        zpool status
        echo
        zfs list
    fi'

collect_shell storage/btrfs \
    'if command -v btrfs >/dev/null 2>&1; then
        btrfs filesystem show
        echo
        btrfs subvolume list /
    fi'

############################################
# Bootloader
############################################

log "Collecting boot configuration..."

collect_shell configuration/bootloader \
    'if command -v efibootmgr >/dev/null 2>&1; then
        echo "=== EFI Boot Entries ==="
        efibootmgr -v
    fi

    echo
    echo "=== GRUB Configuration ==="

    if [ -f /etc/default/grub ]; then
        grep -Ev "^[[:space:]]*(#|$)" /etc/default/grub
    fi'

############################################
# Network
############################################

log "Collecting network configuration..."

collect network/ip-address \
    ip -details address

collect network/routes \
    ip route

collect network/rules \
    ip rule

collect network/link \
    ip -details link

collect network/neighbors \
    ip neigh

collect_shell network/dns \
    'if command -v resolvectl >/dev/null 2>&1; then
        resolvectl status
    elif [ -f /etc/resolv.conf ]; then
        cat /etc/resolv.conf
    fi'

collect_shell network/network-manager \
    'if command -v nmcli >/dev/null 2>&1; then
        nmcli general status
        echo
        nmcli device status
        echo
        nmcli connection show
    fi'

collect_shell network/systemd-networkd \
    'if command -v networkctl >/dev/null 2>&1; then
        networkctl list
        echo
        networkctl status
    fi'

# Do NOT dump NetworkManager system connections because they
# can contain Wi-Fi/VPN credentials.
collect_shell network/networkmanager-connections \
    'if [ -d /etc/NetworkManager/system-connections ]; then
        find /etc/NetworkManager/system-connections \
            -maxdepth 1 \
            -type f \
            -printf "%f\n"
    fi'

############################################
# Firewall
############################################

log "Collecting firewall configuration..."

collect_shell network/firewall \
    'echo "=== UFW ==="
     if command -v ufw >/dev/null 2>&1; then
         ufw status verbose
     fi

     echo
     echo "=== nftables ==="
     if command -v nft >/dev/null 2>&1; then
         nft list ruleset
     fi

     echo
     echo "=== iptables ==="
     if command -v iptables >/dev/null 2>&1; then
         iptables -S
     fi

     echo
     echo "=== firewalld ==="
     if command -v firewall-cmd >/dev/null 2>&1; then
         firewall-cmd --list-all
     fi'

collect network/listening-ports \
    ss -tulpn

############################################
# Package Manager Detection
############################################

log "Detecting package manager..."

PACKAGE_MANAGER="unknown"

if command -v apt-get >/dev/null 2>&1; then
    PACKAGE_MANAGER="apt"

elif command -v pacman >/dev/null 2>&1; then
    PACKAGE_MANAGER="pacman"

elif command -v dnf >/dev/null 2>&1; then
    PACKAGE_MANAGER="dnf"

elif command -v zypper >/dev/null 2>&1; then
    PACKAGE_MANAGER="zypper"

elif command -v apk >/dev/null 2>&1; then
    PACKAGE_MANAGER="apk"

elif command -v rpm >/dev/null 2>&1; then
    PACKAGE_MANAGER="rpm"
fi

echo "$PACKAGE_MANAGER" > "$OUT/packages/package-manager"

############################################
# Packages: Debian / Ubuntu
############################################

if [[ "$PACKAGE_MANAGER" == "apt" ]]; then

    log "Collecting Debian/Ubuntu packages..."

    collect_shell packages/all \
        'dpkg-query -W \
            -f="${binary:Package}\t${Version}\t${Architecture}\n"'

    collect_shell packages/manual \
        'apt-mark showmanual'

    collect_shell packages/automatic \
        'apt-mark showauto'

    collect_shell packages/held \
        'apt-mark showhold'

    collect_shell packages/repositories \
        'grep -RhvE "^[[:space:]]*(#|$)" \
            /etc/apt/sources.list \
            /etc/apt/sources.list.d 2>/dev/null || true'

    collect_shell packages/preferences \
        'find /etc/apt/preferences.d \
            -maxdepth 1 \
            -type f \
            -print \
            -exec cat {} \; 2>/dev/null || true'
fi

############################################
# Packages: Arch
############################################

if [[ "$PACKAGE_MANAGER" == "pacman" ]]; then

    log "Collecting Arch Linux packages..."

    collect_shell packages/all \
        'pacman -Q'

    collect_shell packages/explicit \
        'pacman -Qe'

    collect_shell packages/foreign \
        'pacman -Qm'

    collect_shell packages/native \
        'pacman -Qn'

    collect_shell packages/orphans \
        'pacman -Qtdq 2>/dev/null || true'

    collect_shell packages/repositories \
        'grep -Ev "^[[:space:]]*(#|$)" /etc/pacman.conf'

    # AUR helpers and configuration.
    collect_shell packages/aur-helpers \
        'for cmd in yay paru trizen pikaur; do
            if command -v "$cmd" >/dev/null 2>&1; then
                echo "=== $cmd ==="
                "$cmd" --version
            fi
        done'
fi

############################################
# Packages: Fedora/RHEL
############################################

if [[ "$PACKAGE_MANAGER" == "dnf" || "$PACKAGE_MANAGER" == "rpm" ]]; then

    log "Collecting RPM packages..."

    collect_shell packages/all \
        'rpm -qa --qf "%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n" | sort'

    if command -v dnf >/dev/null 2>&1; then
        collect packages/manual dnf repoquery --userinstalled
        collect packages/repositories dnf repolist --all
    fi
fi

############################################
# Packages: openSUSE
############################################

if [[ "$PACKAGE_MANAGER" == "zypper" ]]; then

    log "Collecting openSUSE packages..."

    collect_shell packages/all \
        'rpm -qa --qf "%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n" | sort'

    collect packages/repositories \
        zypper lr -u

    collect_shell packages/manual \
        'zypper search --installed-only'
fi

############################################
# Packages: Alpine
############################################

if [[ "$PACKAGE_MANAGER" == "apk" ]]; then

    log "Collecting Alpine packages..."

    collect packages/all \
        apk info

    collect packages/world \
        cat /etc/apk/world

    collect_shell packages/repositories \
        'cat /etc/apk/repositories'
fi

############################################
# Snap
############################################

collect_shell packages/snap \
    'if command -v snap >/dev/null 2>&1; then
        snap list
    else
        echo "snap not installed"
    fi'

############################################
# Flatpak
############################################

collect_shell packages/flatpak \
    'if command -v flatpak >/dev/null 2>&1; then
        flatpak list --app \
            --columns=application,version,branch,origin
    else
        echo "flatpak not installed"
    fi'

collect_shell packages/flatpak-runtimes \
    'if command -v flatpak >/dev/null 2>&1; then
        flatpak list --runtime \
            --columns=application,version,branch,origin
    else
        echo "flatpak not installed"
    fi'

############################################
# Development software
############################################

log "Detecting development tools..."

collect_shell packages/development-tools '
commands="
git
gcc
g++
clang
clang++
make
cmake
ninja
meson
python
python3
pip
pip3
node
npm
pnpm
yarn
rustc
cargo
go
java
javac
ruby
gem
perl
php
dotnet
docker
podman
kubectl
helm
terraform
ansible
nix
"

for cmd in $commands; do
    if command -v "$cmd" >/dev/null 2>&1; then
        printf "=== %s ===\n" "$cmd"
        "$cmd" --version 2>&1 | head -n 3
        echo
    fi
done
'

############################################
# Language package managers
############################################

collect_shell packages/python \
    'if command -v python3 >/dev/null 2>&1; then
        python3 -m pip list --format=freeze 2>/dev/null || true
    fi'

collect_shell packages/node-global \
    'if command -v npm >/dev/null 2>&1; then
        npm list -g --depth=0 2>/dev/null || true
    fi'

collect_shell packages/ruby \
    'if command -v gem >/dev/null 2>&1; then
        gem list
    fi'

collect_shell packages/rust-tools \
    'if command -v cargo >/dev/null 2>&1; then
        cargo install --list 2>/dev/null || true
    fi'

############################################
# Services
############################################

log "Collecting services..."

if command -v systemctl >/dev/null 2>&1; then

    collect services/all \
        systemctl list-unit-files --type=service --no-pager

    collect services/running \
        systemctl list-units --type=service --state=running --no-pager

    collect services/enabled \
        systemctl list-unit-files --type=service --state=enabled --no-pager

    collect services/failed \
        systemctl --failed --no-pager

    collect services/timers \
        systemctl list-timers --all --no-pager

    collect services/sockets \
        systemctl list-unit-files --type=socket --no-pager

    collect services/targets \
        systemctl list-unit-files --type=target --no-pager

    collect_shell services/custom-units \
        'find \
            /etc/systemd/system \
            /usr/local/lib/systemd/system \
            -type f \
            \( -name "*.service" \
               -o -name "*.timer" \
               -o -name "*.socket" \
               -o -name "*.path" \
               -o -name "*.mount" \) \
            -print 2>/dev/null'
fi

############################################
# Systemd overrides
############################################

collect_shell services/systemd-overrides \
    'find /etc/systemd/system \
        -type f \
        \( -name "*.conf" -o -path "*/.d/*" \) \
        -print 2>/dev/null'

############################################
# Cron
############################################

log "Collecting scheduled tasks..."

collect_shell services/cron-system \
    'find \
        /etc/cron.d \
        /etc/cron.daily \
        /etc/cron.hourly \
        /etc/cron.monthly \
        /etc/cron.weekly \
        -type f \
        -print 2>/dev/null'

collect_shell services/cron-users '
if [ -d /var/spool/cron ]; then
    find /var/spool/cron \
        -type f \
        -not -name "*.lock" \
        -print 2>/dev/null
fi

if [ -d /var/spool/cron/crontabs ]; then
    find /var/spool/cron/crontabs \
        -type f \
        -not -name "*.lock" \
        -print 2>/dev/null
fi
'

############################################
# Users and groups
############################################

log "Collecting users and groups..."

collect users/passwd \
    getent passwd

collect users/groups \
    getent group

collect_shell users/normal-users \
    'awk -F: '"'"'($3 >= 1000 && $3 < 60000) {print}'"'"' /etc/passwd'

collect_shell users/user-shells \
    'getent passwd | awk -F: "{print \$1 \": \" \$7}"'

collect_shell users/sudo \
    'echo "=== /etc/sudoers ==="
     grep -Ev "^[[:space:]]*(#|$)" /etc/sudoers 2>/dev/null || true

     echo
     echo "=== /etc/sudoers.d ==="
     find /etc/sudoers.d \
         -type f \
         -not -name "*~" \
         -print \
         -exec grep -Ev "^[[:space:]]*(#|$)" {} \; \
         2>/dev/null || true'

collect_shell users/groups-important \
    'for group in wheel sudo docker libvirt video render audio plugdev; do
        if getent group "$group" >/dev/null 2>&1; then
            getent group "$group"
        fi
    done'

############################################
# SSH configuration
############################################

log "Collecting SSH configuration..."

collect_shell configuration/ssh '
if [ -f /etc/ssh/sshd_config ]; then
    sed -E \
        -e "/^[[:space:]]*#/d" \
        -e "/^[[:space:]]*$/d" \
        -e "/(password|secret|token|key).*=/Id" \
        /etc/ssh/sshd_config
else
    echo "sshd_config not found"
fi
'

collect_shell configuration/ssh-files '
find /etc/ssh \
    -maxdepth 1 \
    -type f \
    \( -name "*.conf" -o -name "sshd_config" \) \
    -printf "%f\n" 2>/dev/null
'

############################################
# Kernel configuration
############################################

log "Collecting kernel configuration..."

collect_shell configuration/sysctl \
    'grep -RhvE "^[[:space:]]*(#|$)" \
        /etc/sysctl.conf \
        /etc/sysctl.d 2>/dev/null || true'

collect_shell configuration/modules \
    'grep -RhvE "^[[:space:]]*(#|$)" \
        /etc/modules \
        /etc/modules-load.d 2>/dev/null || true'

collect_shell configuration/modprobe \
    'find /etc/modprobe.d \
        -type f \
        -maxdepth 1 \
        -print \
        -exec grep -Ev "^[[:space:]]*(#|$)" {} \; \
        2>/dev/null || true'

############################################
# Udev
############################################

collect_shell configuration/udev \
    'find /etc/udev/rules.d \
        -type f \
        -name "*.rules" \
        -print 2>/dev/null'

############################################
# Common server software
############################################

log "Checking common server software..."

collect_shell configuration/server-software '
for directory in \
    nginx \
    apache2 \
    httpd \
    caddy \
    docker \
    containerd \
    podman \
    libvirt \
    postgresql \
    mysql \
    mariadb \
    redis \
    prometheus \
    grafana \
    samba \
    bind \
    named \
    chrony \
    openvpn \
    wireguard
do
    if [ -d "/etc/$directory" ]; then
        echo "=== /etc/$directory ==="
        find "/etc/$directory" \
            -maxdepth 2 \
            -type f \
            -printf "%p\n" \
            2>/dev/null
        echo
    fi
done
'

############################################
# /usr/local /opt /srv
############################################

collect_shell configuration/local-software \
    'for directory in /usr/local /opt /srv; do
        if [ -d "$directory" ]; then
            echo "=== $directory ==="
            find "$directory" \
                -maxdepth 3 \
                -type f \
                -printf "%p\n" \
                2>/dev/null
            echo
        fi
    done'

############################################
# Desktop environment
############################################

collect_shell configuration/desktop '
echo "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-}"
echo "XDG_SESSION_DESKTOP=${XDG_SESSION_DESKTOP:-}"
echo "DESKTOP_SESSION=${DESKTOP_SESSION:-}"
echo

if command -v dpkg-query >/dev/null 2>&1; then
    dpkg-query -W -f="${binary:Package}\n" 2>/dev/null |
        grep -Ei "gnome|kde|plasma|xfce|mate|cinnamon|lxde|lxqt|sway|i3|wayland|xorg" || true

elif command -v pacman >/dev/null 2>&1; then
    pacman -Q 2>/dev/null |
        grep -Ei "gnome|kde|plasma|xfce|mate|cinnamon|lxde|lxqt|sway|i3|wayland|xorg" || true
fi
'

############################################
# Environment - REDACTED
############################################

collect_shell configuration/environment '
for file in \
    /etc/environment \
    /etc/profile \
    /etc/bash.bashrc \
    /etc/zshrc
do
    if [ -f "$file" ]; then
        echo "=== $file ==="

        sed -E \
            -e "/^[[:space:]]*#/d" \
            -e "/^[[:space:]]*$/d" \
            -e "s/((PASSWORD|PASSWD|TOKEN|SECRET|API_KEY|APIKEY|PRIVATE_KEY|CREDENTIAL)[A-Za-z0-9_]*)=.*/\1=<REDACTED>/Ig" \
            "$file"

        echo
    fi
done
'

############################################
# Running processes
############################################

collect system/processes \
    ps auxww

############################################
# Logs / problems
############################################

log "Collecting diagnostic information..."

if command -v journalctl >/dev/null 2>&1; then

    collect logs/boot-errors \
        journalctl -b -p warning --no-pager

    collect logs/failed-services \
        systemctl --failed --no-pager
fi

############################################
# Installed binaries
############################################

collect_shell system/path-binaries '
printf "%s\n" "$PATH" | tr ":" "\n" |
while read -r directory; do
    if [ -d "$directory" ]; then
        echo "=== $directory ==="
        find "$directory" -maxdepth 1 -type f -executable \
            -printf "%f\n" 2>/dev/null |
            sort
    fi
done
'

############################################
# Package summary
############################################

log "Creating package summary..."

collect_shell packages/summary '
echo "Distribution: '"$DISTRO_NAME"'"
echo "Package manager: '"$PACKAGE_MANAGER"'"
echo

case "'"$PACKAGE_MANAGER"'" in
    apt)
        echo "Installed:"
        dpkg-query -W 2>/dev/null | wc -l

        echo "Manual:"
        apt-mark showmanual 2>/dev/null | wc -l
        ;;

    pacman)
        echo "Installed:"
        pacman -Q 2>/dev/null | wc -l

        echo "Explicit:"
        pacman -Qe 2>/dev/null | wc -l

        echo "Foreign/AUR:"
        pacman -Qm 2>/dev/null | wc -l
        ;;

    dnf|rpm)
        echo "Installed:"
        rpm -qa 2>/dev/null | wc -l
        ;;

    zypper)
        echo "Installed:"
        rpm -qa 2>/dev/null | wc -l
        ;;

    apk)
        echo "Installed:"
        apk info 2>/dev/null | wc -l
        ;;
esac
'

############################################
# Nix detection
############################################

collect_shell packages/existing-nix \
    'if command -v nix >/dev/null 2>&1; then
        nix --version
        echo
        nix-channel --list 2>/dev/null || true
    else
        echo "Nix is not installed"
    fi'

############################################
# Potential secrets audit
############################################

log "Checking inventory for potentially sensitive filenames..."

find "$OUT" \
    -type f \
    \( \
        -iname "*password*" \
        -o -iname "*passwd*" \
        -o -iname "*secret*" \
        -o -iname "*credential*" \
        -o -iname "*token*" \
        -o -iname "*private*" \
        -o -iname "*.pem" \
        -o -iname "*.key" \
        -o -iname ".env*" \
    \) \
    -print \
    > "$OUT/logs/sensitive-file-review.txt" 2>/dev/null || true

############################################
# Generate README
############################################

cat > "$OUT/README.md" <<EOF
# NixOS Migration Inventory

This inventory was generated by \`nixos-inventory.sh\`. It is migration input,
not a NixOS configuration and not a backup.

## Machine

- Hostname: $HOST_NAME
- Distribution: $DISTRO_NAME
- Distribution family: $DISTRO_FAMILY
- Distribution version: $DISTRO_VERSION
- Package manager: $PACKAGE_MANAGER
- Collected: $(date --iso-8601=seconds 2>/dev/null || date)

## Directory structure

### metadata/

Basic operating-system and machine information.

### hardware/

CPU, RAM, PCI, USB, GPU and kernel-module information.

### storage/

Disks, filesystems, mounts, LUKS, LVM, RAID, ZFS and Btrfs.

### network/

Interfaces, routes, DNS, firewall and listening ports.

### packages/

Installed packages and package-manager information.

### services/

Systemd services, timers, sockets and scheduled jobs.

### users/

Users, groups, shells and sudo configuration.

### configuration/

Important configuration references and custom software locations.

### logs/

Diagnostic information.

## Important

This inventory is intended as input for a NixOS migration.

Do not blindly convert every package to NixOS.

The preferred migration strategy is:

1. Identify what the machine actually does.
2. Identify the services it provides.
3. Identify hardware-specific requirements.
4. Map services to NixOS modules.
5. Map packages to nixpkgs packages.
6. Move user-specific configuration to Home Manager where appropriate.
7. Handle secrets separately with sops-nix or agenix.
8. Test the resulting configuration in a VM.
9. Deploy to the physical machine.

Review \`logs/sensitive-file-review.txt\` before committing the inventory
to a Git repository. Re-run the collector with \`--force\` to replace an
existing inventory, or \`--no-archive\` when an archive is not wanted.
EOF

############################################
# Inventory manifest
############################################

log "Generating manifest..."

find "$OUT" \
    -type f \
    -printf "%P\n" \
    2>/dev/null |
    sort > "$OUT/manifest.txt"

############################################
# Archive
############################################

ARCHIVE="${BASE_DIR}/${HOST_NAME}.tar.gz"

if ((CREATE_ARCHIVE == 1)); then
    if ((FORCE == 1)) && [[ -f "$ARCHIVE" ]]; then
        rm -f -- "$ARCHIVE" || warn "Unable to remove existing archive: $ARCHIVE"
    fi
    if command -v tar >/dev/null 2>&1; then
        log "Creating archive..."

        if ! tar \
            --exclude='*/logs/script.log' \
            -czf "$ARCHIVE" \
            -C "$BASE_DIR" \
            "$HOST_NAME" 2>/dev/null; then
            warn "Unable to create archive: $ARCHIVE"
        fi
    else
        warn "tar is not installed; skipping archive creation."
    fi
fi

############################################
# Final report
############################################

echo
echo "${BOLD}==============================================${RESET}"
echo "${BOLD} NixOS Migration Inventory Complete${RESET}"
echo "${BOLD}==============================================${RESET}"
echo
echo "Host:           $HOST_NAME"
echo "Distribution:   $DISTRO_NAME"
echo "Family:         $DISTRO_FAMILY"
echo "Package mgr:    $PACKAGE_MANAGER"
echo
echo "Inventory:"
echo "  $OUT"
echo
if ((CREATE_ARCHIVE == 1)) && [[ -f "$ARCHIVE" ]]; then
    echo "Archive:"
    echo "  $ARCHIVE"
fi
echo
echo "Files collected:"
find "$OUT" -type f | wc -l
echo
echo "${YELLOW}Review logs/sensitive-file-review.txt before sharing the inventory.${RESET}"
echo
