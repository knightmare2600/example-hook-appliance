#!/bin/bash

set -euo pipefail

PRIMARY_IF="$(ip route | awk '/default/ {print $5}' | head -n1)"
if [ -z "${PRIMARY_IF}" ]; then
  PRIMARY_IF="eth0"
fi

IPADDR="$(ip -4 addr show "${PRIMARY_IF}" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)"
SUBNET="$(echo "${IPADDR}" | awk -F. '{print $1"."$2"."$3}')"
DEPLOY_HOST="${SUBNET}.10"
MOUNTPOINT="/mnt/deploytools"
mkdir -p "${MOUNTPOINT}"

echo
echo "=================================================="
echo "SMB AUTHENTICATION REQUIRED"
echo "=================================================="

read -p "Username [jukebox.internal\\Administrator]: " USERNAME
if [ -z "${USERNAME}" ]; then
  USERNAME="jukebox.internal\\Administrator"
fi

read -s -p "Password: " PASSWORD
echo

cat > /tmp/smb-credentials.$$ << EOF
username=${USERNAME}
password=${PASSWORD}
domain=jukebox.internal
EOF

chmod 600 /tmp/smb-credentials.$$

mount -t cifs "//${DEPLOY_HOST}/DeployTools" "${MOUNTPOINT}" -o "credentials=/tmp/smb-credentials.$$,vers=3.0,iocharset=utf8"
mkdir -p "${MOUNTPOINT}/inventory"
cp -f /root/inventory/*.json "${MOUNTPOINT}/inventory/" || true
sync
umount "${MOUNTPOINT}" || true
rm -f /tmp/smb-credentials.$$
echo "[+] Upload complete"
