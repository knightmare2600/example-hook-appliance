#!/bin/bash

set -euo pipefail

OUTDIR="/root/inventory"
TMPDIR="/tmp/hwcollect"

mkdir -p "${OUTDIR}"
mkdir -p "${TMPDIR}"

## Determine primary MAC
PRIMARY_IF="$(ip route | awk '/default/ {print $5}' | head -n1)"
if [ -z "${PRIMARY_IF}" ]; then
  PRIMARY_IF="eth0"
fi

MAC="$(cat /sys/class/net/${PRIMARY_IF}/address | tr ':' '-')"

JSON_OUT="${OUTDIR}/${MAC}.json"
echo "[*] Collecting hardware inventory..."
ip -j addr > "${TMPDIR}/network.json"
lsblk -J > "${TMPDIR}/blockdevices.json"
lspci -mm > "${TMPDIR}/lspci.txt" || true
lsusb > "${TMPDIR}/lsusb.txt" || true
dmidecode > "${TMPDIR}/dmidecode.txt" || true

jq -n --arg hostname "$(hostname)" --arg kernel "$(uname -a)" --arg mac "${MAC}" --slurpfile network "${TMPDIR}/network.json" --slurpfile blockdevices "${TMPDIR}/blockdevices.json" --rawfile lspci "${TMPDIR}/lspci.txt" --rawfile lsusb "${TMPDIR}/lsusb.txt" --rawfile dmidecode "${TMPDIR}/dmidecode.txt" \
  '{
    hostname: $hostname,
    kernel: $kernel,
    primary_mac: $mac,
    network: $network[0],
    blockdevices: $blockdevices[0],
    lspci: $lspci,
    lsusb: $lsusb,
    dmidecode: $dmidecode
  }' > "${JSON_OUT}"

chmod 600 "${JSON_OUT}"
echo "[+] Inventory written to ${JSON_OUT}"
