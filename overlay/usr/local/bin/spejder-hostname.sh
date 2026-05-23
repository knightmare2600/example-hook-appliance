#!/bin/bash
# spejder-hostname.sh
# Sets hostname to spejder-<mac-address> at boot time
# Refreshes /etc/hostname and /etc/hosts so all tools see the correct name
#
# Version history:
# 0.1.0 - Initial version

# Solarized dark palette - deuteranopes (red/green colourblind) safe
CY="\e[38;5;37m"   # Cyan       - information
GR="\e[38;5;64m"   # Green      - success / ok
YL="\e[38;5;136m"  # Yellow     - warning
OR="\e[38;5;166m"  # Orange     - non-fatal error
RD="\e[38;5;160m"  # Red        - fatal error
RS="\e[0m"         # Reset

info()    { echo -e "${CY}[spejder-hostname]${RS} $*"; }
ok()      { echo -e "${GR}[spejder-hostname]${RS} $*"; }
warn()    { echo -e "${YL}[spejder-hostname]${RS} $*"; }
err()     { echo -e "${RD}[spejder-hostname]${RS} $*" >&2; }

# Wait for eth0 to appear in sysfs (udev may not have settled yet)
MAX_WAIT=10
WAITED=0
while [ ${WAITED} -lt ${MAX_WAIT} ]; do
  if [ -f /sys/class/net/eth0/address ]; then
    break
  fi
  sleep 1
  WAITED=$((WAITED + 1))
done

if [ ! -f /sys/class/net/eth0/address ]; then
  warn "eth0 not found after ${MAX_WAIT}s - keeping default hostname"
  exit 0
fi

MAC=$(cat /sys/class/net/eth0/address | tr ':' '-')
HOSTNAME="spejder-${MAC}"

info "Setting hostname to ${HOSTNAME}..."

# Set the running hostname
hostnamectl set-hostname "${HOSTNAME}"

# Update /etc/hostname
echo "${HOSTNAME}" > /etc/hostname

# Update /etc/hosts - replace or add 127.0.1.1 entry
if grep -q "^127\.0\.1\.1" /etc/hosts; then
  sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME}/" /etc/hosts
else
  echo -e "127.0.1.1\t${HOSTNAME}" >> /etc/hosts
fi

ok "Hostname set to ${HOSTNAME}"
