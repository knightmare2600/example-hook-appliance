#!/bin/sh

set -eu

SERVER="http://192.168.139.50"

SERIAL="$(cat /sys/class/dmi/id/product_serial 2>/dev/null || echo unknown)"
MODEL="$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
HOSTNAME="$(hostname)"
ARCH="$(uname -m)"

mkdir -p /tmp/inventory

cat > /tmp/inventory/inventory.json <<EOF
{
  "hostname": "${HOSTNAME}",
  "serial": "${SERIAL}",
  "model": "${MODEL}",
  "arch": "${ARCH}"
}
EOF

curl -X POST -H "Content-Type: application/json" --data @/tmp/inventory/inventory.json "${SERVER}/inventory"

poweroff -f
