#!/bin/bash
# smbupload.sh - SMB inventory uploader for Spejder provisioning runtime
# Credentials are ALWAYS entered interactively - never stored beyond the session
# Version history:
# 0.1.0 - Initial version
# 0.2.0 - Added trap-based credential file cleanup (survives set -euo pipefail exits)
#          Added colourblind-safe solarized dark output
#          Added wait for hwcollect inventory before attempting upload
#          Added input validation on credentials
set -euo pipefail

# Solarized dark palette - chosen for deuteranopes (red/green colourblind)
# RGB values are deliberately shifted from pure red/green to remain distinguishable
CY="\e[38;5;37m"   # Cyan       - information
GR="\e[38;5;64m"   # Green      - success / ok
YL="\e[38;5;136m"  # Yellow     - warning
OR="\e[38;5;166m"  # Orange     - non-fatal error (burnt, distinct from yellow and red for deuteranopes)
RD="\e[38;5;160m"  # Red        - error / fatal
RS="\e[0m"         # Reset

info()    { echo -e "${CY}[INFO]${RS}    $*"; }
ok()      { echo -e "${GR}[OK]${RS}      $*"; }
warn()    { echo -e "${YL}[WARN]${RS}    $*"; }
nonfatal(){ echo -e "${OR}[NOTICE]${RS}  $*"; }
err()     { echo -e "${RD}[ERROR]${RS}   $*" >&2; }

OUTDIR="/root/inventory"
MOUNTPOINT="/mnt/deploytools"
CRED_FILE="/tmp/.smb-credentials.$$"

##############################################################################
# Trap - guarantee credential file is wiped on any exit path
##############################################################################
cleanup() {
  if [ -f "${CRED_FILE}" ]; then
    rm -f "${CRED_FILE}"
    info "Credential file removed"
  fi
  if mountpoint -q "${MOUNTPOINT}" 2>/dev/null; then
    umount "${MOUNTPOINT}" 2>/dev/null || true
    info "Share unmounted"
  fi
}
trap cleanup EXIT INT TERM

##############################################################################
# Wait for hwcollect inventory to exist
##############################################################################
info "Checking for inventory data..."

MAX_WAIT=300
WAITED=0

while [ ${WAITED} -lt ${MAX_WAIT} ]; do
  JSON_COUNT="$(find "${OUTDIR}" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)"
  if [ "${JSON_COUNT}" -gt 0 ]; then
    ok "Found ${JSON_COUNT} inventory file(s) in ${OUTDIR}"
    break
  fi
  warn "No inventory files found yet - waiting for hwcollect to complete..."
  sleep 5
  WAITED=$((WAITED + 5))
done

if [ "${JSON_COUNT}" -eq 0 ]; then
  err "No inventory files found in ${OUTDIR} after ${MAX_WAIT}s"
  err "Run hwcollect.sh first - aborting upload"
  exit 1
fi

echo
info "Inventory files to upload:"
for f in "${OUTDIR}"/*.json; do
  echo -e "  ${CY}→${RS} $(basename "${f}")"
done
echo

##############################################################################
# Determine deploy host from default route
##############################################################################
PRIMARY_IF="$(ip route 2>/dev/null | awk '/default/ {print $5}' | head -n1)"
[ -z "${PRIMARY_IF}" ] && PRIMARY_IF="eth0"

IPADDR="$(ip -4 addr show "${PRIMARY_IF}" 2>/dev/null \
  | awk '/inet / {print $2}' \
  | cut -d/ -f1 \
  | head -n1)"

if [ -z "${IPADDR}" ]; then
  err "No IP address on ${PRIMARY_IF} - cannot determine deploy host"
  exit 1
fi

SUBNET="$(echo "${IPADDR}" | awk -F. '{print $1"."$2"."$3}')"
DEPLOY_HOST="${SUBNET}.10"

info "Deploy host: ${DEPLOY_HOST}"
info "Share:       \\\\${DEPLOY_HOST}\\DeployTools"
echo

##############################################################################
# Prompt for credentials - always interactive, never stored beyond this session
##############################################################################
echo -e "${YL}=================================================${RS}"
echo -e "${YL}  SMB AUTHENTICATION REQUIRED${RS}"
echo -e "${YL}=================================================${RS}"
echo

read -rp "$(echo -e "${CY}Username${RS} [jukebox.internal\\Administrator]: ")" USERNAME
if [ -z "${USERNAME}" ]; then
  USERNAME="jukebox.internal\\Administrator"
fi

read -rsp "$(echo -e "${CY}Password${RS}: ")" PASSWORD
echo

if [ -z "${PASSWORD}" ]; then
  err "Password cannot be empty"
  exit 1
fi

##############################################################################
# Write credential file - trap guarantees removal on any exit
##############################################################################
touch "${CRED_FILE}"
chmod 600 "${CRED_FILE}"
cat > "${CRED_FILE}" << EOF
username=${USERNAME}
password=${PASSWORD}
domain=jukebox.internal
EOF

##############################################################################
# Mount share
##############################################################################
mkdir -p "${MOUNTPOINT}"

info "Mounting //${DEPLOY_HOST}/DeployTools..."
if ! mount -t cifs "//${DEPLOY_HOST}/DeployTools" "${MOUNTPOINT}" \
  -o "credentials=${CRED_FILE},vers=3.0,iocharset=utf8"; then
  err "Failed to mount //${DEPLOY_HOST}/DeployTools"
  err "Check credentials, network connectivity, and that the share exists"
  exit 1
fi
ok "Share mounted at ${MOUNTPOINT}"

##############################################################################
# Upload inventory
##############################################################################
mkdir -p "${MOUNTPOINT}/inventory"

UPLOADED=0
FAILED=0

for f in "${OUTDIR}"/*.json; do
  FNAME="$(basename "${f}")"
  info "Uploading ${FNAME}..."
  if cp -f "${f}" "${MOUNTPOINT}/inventory/"; then
    ok "Uploaded ${FNAME}"
    UPLOADED=$((UPLOADED + 1))
  else
    nonfatal "Failed to upload ${FNAME}"
    FAILED=$((FAILED + 1))
  fi
done

sync

echo
if [ ${FAILED} -eq 0 ]; then
  ok "Upload complete - ${UPLOADED} file(s) uploaded successfully"
else
  warn "Upload finished - ${UPLOADED} succeeded, ${FAILED} failed"
fi

# trap handles unmount and credential cleanup on exit

