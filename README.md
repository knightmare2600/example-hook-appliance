# Example Hook Appliance

Minimal multi-arch Hook appliance for:

- PXE/iPXE boot
- hardware inventory
- JSON reporting
- stateless discovery

## Architectures

- amd64
- arm64

## Outputs

GitHub Actions produces:

- hook-kernel
- hook-initrd.img
- hook-cmdline

## Boot

Use:

ipxe/discovery.ipxe
