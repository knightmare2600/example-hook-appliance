# Spejder — Hardware Provisioning Runtime

> *Spejder* (Danish: scout/ranger) — sent ahead to gather intelligence and report back.

A minimal, stateless, multi-architecture provisioning runtime built on Debian Trixie.
Boots via iPXE, collects hardware inventory, and uploads it to a deployment share.
No persistent storage. No installer. No nonsense.

---

## What it does

1. Boots via PXE/iPXE into a fully self-contained initramfs
2. Waits for a routable network interface (rejects APIPA and loopback)
3. Collects a comprehensive hardware inventory as a JSON file named by MAC address
4. Drops to an autologin shell on tty1
5. Operator runs `smbupload.sh`, enters credentials interactively, and uploads the inventory to a deployment share

Credentials are **never stored** — they exist only for the duration of the SMB mount and are wiped on exit, error, or signal via `trap`.

---

## Architectures

| Architecture | Kernel | Status |
|---|---|---|
| `amd64` | 6.12.73+deb13-amd64 | ✅ Supported |
| `arm64` | 6.12.73+deb13-arm64 | ✅ Supported |

---

## Collected inventory

`hwcollect.sh` gathers the following and assembles them into a single JSON file at `/root/inventory/<MAC>.json`:

| Field | Source |
|---|---|
| Hostname | `hostname` |
| Kernel | `uname -a` |
| Primary MAC + IP | `ip route` / `ip addr` |
| Network interfaces | `ip -j addr` |
| Block devices | `lsblk -J` |
| PCI devices | `lspci -mm` |
| USB devices | `lsusb` |
| DMI/SMBIOS data | `dmidecode` |
| NVMe inventory | `nvme list` |
| IPMI/BMC FRU data | `ipmitool fru print` |
| RAID status | `/proc/mdstat` |
| SMART data | `smartctl -a` |

Missing tools or absent hardware produce empty fields rather than aborting the run.

---

## Repository layout

```
.
├── .github/
│   └── workflows/
│       ├── build.yml        # Builds initramfs for both arches
│       └── preflight.yml    # Warms caches, commits kernel debs to sources/
├── build/
│   ├── build_packages.txt   # Packages for the CI build environment only
│   ├── initrd_packages.txt  # Packages installed inside the initramfs
│   └── shared_packages.txt  # Packages needed in both contexts
├── ipxe/
│   └── discovery.ipxe       # iPXE boot menu entry
├── overlay/
│   ├── etc/                 # Configuration overlaid into the rootfs
│   │   ├── apt/sources.list
│   │   ├── default/locale
│   │   ├── modprobe.d/      # autofs4 alias, etc.
│   │   ├── ssh/sshd_config.d/10-appliance.conf
│   │   └── systemd/
│   │       ├── network/20-wired.network
│   │       └── system/
│   │           ├── getty@tty1.service.d/autologin.conf
│   │           ├── hwcollect.service
│   │           └── smbupload.service
│   └── usr/local/bin/
│       ├── hwcollect.sh     # Hardware inventory collector
│       └── smbupload.sh     # Interactive SMB uploader
├── shared/
│   └── locale.gen           # Single source of truth for locale generation
│                            # (en_GB, da_DK, de_DE — everyone else can whistle)
└── sources/
    ├── *.deb                # Kernel debs committed by preflight.yml
    └── firmware-*/          # Firmware deb cache (gitignored, populated by preflight)
```

---

## Getting started

### Prerequisites

This repo uses [Git LFS](https://git-lfs.github.com) to store kernel `.deb` files
in `sources/`. Without LFS installed you'll get pointer files instead of the actual
binaries and the build will fall back to downloading them.

On Debian/Ubuntu:
```bash
sudo apt-get install git-lfs
git lfs install
```

On macOS:
```bash
brew install git-lfs
git lfs install
```

Fresh clone:
```bash
git clone https://github.com/knightmare2600/Spejder
cd Spejder
git lfs pull
```

---

## Build

Run **Preflight Cache Warmer** manually via Actions → `preflight.yml` → Run workflow.

This downloads the kernel debs for both arches, commits them to `sources/`, and
pre-warms the firmware and apt package caches. Takes ~15 minutes but only needs
running when you want to deliberately refresh cached artefacts.

### Normal build

Run **Build Provisioning Runtime** via Actions → `build.yml` → Run workflow.

With warm caches this is significantly faster — the kernel deb comes from `sources/`
in the repo, firmware and apt packages restore from cache, and only overlay changes
and final image assembly need to happen fresh.

### Cache layers

| Layer | Cache key | What it saves |
|---|---|---|
| Kernel `.deb` | committed to `sources/` | ~60MB download, eliminates mirror dependency |
| Firmware debs | hash of `initrd_packages.txt` | ~30MB download |
| Rootfs apt packages | hash of package lists | ~200–400MB download |
| Build host apt | hash of build package lists | ~150MB download |

### Build outputs

| File | Description |
|---|---|
| `initramfs-amd64.cpio.gz` | amd64 initramfs image |
| `initramfs-arm64.cpio.gz` | arm64 initramfs image |
| `linux-image-*.deb` | Pinned kernel package for each arch |
| `installed-manifest.txt` | Full `dpkg -l` output baked into the image at `/root/` |

---

## Boot

Point your iPXE server at `ipxe/discovery.ipxe`. The kernel line uses:

```
console=ttyS0,115200 console=tty0 rw net.ifnames=0 biosdevname=0
```

`net.ifnames=0` and `biosdevname=0` guarantee the primary NIC is always `eth0`,
which `systemd-networkd` picks up via `overlay/etc/systemd/network/20-wired.network`
(`Name=eth*`, DHCP=yes, DNS via Cloudflare and Quad9).

---

## Runtime operation

Once booted:

```
# Hardware collection runs automatically after network-online.target
# Check status:
systemctl status hwcollect.service

# View collected inventory:
ls /root/inventory/
cat /root/inventory/<MAC>.json | jq .

# Upload to deployment share:
smbupload.sh
# → prompts for username and password interactively
# → mounts //192.168.x.10/DeployTools
# → copies inventory JSON to DeployTools/inventory/
# → unmounts and wipes credentials
```

The SMB deploy host is derived automatically from the default gateway subnet
(last octet `.10`). Credentials are always entered interactively — they are never
stored in files, environment variables, or logs beyond the lifetime of the mount.

---

## Colour scheme

All console output uses the Solarized dark palette, chosen specifically for
**deuteranopes** (red/green colour blindness) and low-contrast visibility:

| Colour | Meaning |
|---|---|
| Cyan | Informational |
| Green | Success / OK |
| Yellow | Warning |
| Orange (burnt) | Non-fatal error |
| Red | Fatal error |

---

## Acknowledgements

Built on [Debian Trixie](https://www.debian.org/), [systemd](https://systemd.io/),
and [iPXE](https://ipxe.org/).
Inspired by the [Tinkerbell Hook](https://github.com/tinkerbell/hook) project.
Built at [github.com/knightmare2600/Spejder](https://github.com/knightmare2600/Spejder).
