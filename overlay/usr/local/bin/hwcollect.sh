#!/bin/bash
# hwcollect.sh - Hardware inventory collector for Spejder provisioning runtime
# Version history:
# 0.1.0 - Initial version
# 0.2.0 - Renamed TMPDIR to HW_TMPDIR to avoid overriding system variable
#          Added network readiness wait with colourblind-safe solarized dark output
#          Added colourblind-safe status output throughout
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
HW_TMPDIR="/tmp/hwcollect"

mkdir -p "${OUTDIR}"
mkdir -p "${HW_TMPDIR}"

##############################################################################
# Wait for a routable non-loopback non-APIPA interface
##############################################################################
info "Waiting for a routable network interface..."

MAX_WAIT=120
WAITED=0
PRIMARY_IF=""

while [ ${WAITED} -lt ${MAX_WAIT} ]; do
  # Find default route interface
  CANDIDATE="$(ip route 2>/dev/null | awk '/default/ {print $5}' | head -n1)"

  if [ -n "${CANDIDATE}" ]; then
    IPADDR="$(ip -4 addr show "${CANDIDATE}" 2>/dev/null \
      | awk '/inet / {print $2}' \
      | cut -d/ -f1 \
      | head -n1)"

    if [ -n "${IPADDR}" ]; then
      # Reject loopback and APIPA (169.254.x.x)
      case "${IPADDR}" in
        127.*|169.254.*)
          warn "Interface ${CANDIDATE} has non-routable address ${IPADDR} - waiting..."
          ;;
        *)
          PRIMARY_IF="${CANDIDATE}"
          break
          ;;
      esac
    fi
  fi

  sleep 2
  WAITED=$((WAITED + 2))
  info "No routable interface yet - ${WAITED}s elapsed of ${MAX_WAIT}s maximum..."
done

if [ -z "${PRIMARY_IF}" ]; then
  err "No routable interface found after ${MAX_WAIT}s - cannot determine primary MAC"
  err "Network inventory will be incomplete"
  PRIMARY_IF="eth0"
  nonfatal "Falling back to eth0 - JSON output may be incomplete"
fi

IPADDR="$(ip -4 addr show "${PRIMARY_IF}" 2>/dev/null \
  | awk '/inet / {print $2}' \
  | cut -d/ -f1 \
  | head -n1 || echo "unknown")"

MAC="$(cat /sys/class/net/${PRIMARY_IF}/address 2>/dev/null \
  | tr ':' '-' || echo "unknown")"

ok "Primary interface: ${PRIMARY_IF}  IP: ${IPADDR}  MAC: ${MAC}"

JSON_OUT="${OUTDIR}/${MAC}.json"

##############################################################################
# Collect hardware inventory
##############################################################################
info "Collecting network configuration..."
ip -j addr > "${HW_TMPDIR}/network.json" \
  && ok "Network configuration collected" \
  || nonfatal "Network collection incomplete"

info "Collecting block devices..."
lsblk -J > "${HW_TMPDIR}/blockdevices.json" \
  && ok "Block devices collected" \
  || nonfatal "Block device collection incomplete"

info "Collecting PCI devices..."
lspci -mm > "${HW_TMPDIR}/lspci.txt" 2>/dev/null \
  && ok "PCI devices collected" \
  || nonfatal "lspci unavailable or returned no data"

info "Collecting USB devices..."
lsusb > "${HW_TMPDIR}/lsusb.txt" 2>/dev/null \
  && ok "USB devices collected" \
  || nonfatal "lsusb unavailable or returned no data"

info "Collecting DMI/SMBIOS data..."
dmidecode > "${HW_TMPDIR}/dmidecode.txt" 2>/dev/null \
  && ok "DMI data collected" \
  || nonfatal "dmidecode unavailable or returned no data"

info "Collecting NVMe inventory..."
nvme list > "${HW_TMPDIR}/nvme.txt" 2>/dev/null \
  && ok "NVMe inventory collected" \
  || nonfatal "nvme-cli unavailable or no NVMe devices present"

info "Collecting IPMI/BMC data..."
ipmitool fru print > "${HW_TMPDIR}/ipmi_fru.txt" 2>/dev/null \
  && ok "IPMI FRU data collected" \
  || nonfatal "ipmitool unavailable or no BMC present - skipping"

info "Collecting RAID status..."
cat /proc/mdstat > "${HW_TMPDIR}/mdstat.txt" 2>/dev/null \
  && ok "RAID status collected" \
  || nonfatal "mdstat unavailable"

info "Collecting SMART data..."
for dev in /dev/sd? /dev/nvme?; do
  [ -e "${dev}" ] || continue
  smartctl -a "${dev}" >> "${HW_TMPDIR}/smart.txt" 2>/dev/null || true
done
[ -s "${HW_TMPDIR}/smart.txt" ] \
  && ok "SMART data collected" \
  || nonfatal "No SMART data available"

##############################################################################
# Assemble JSON
##############################################################################
info "Assembling inventory JSON..."

# Ensure all optional files exist so jq --rawfile does not fail
for f in lspci lsusb dmidecode nvme ipmi_fru mdstat smart; do
  touch "${HW_TMPDIR}/${f}.txt"
done
[ -f "${HW_TMPDIR}/network.json" ]      || echo '[]' > "${HW_TMPDIR}/network.json"
[ -f "${HW_TMPDIR}/blockdevices.json" ] || echo '{}' > "${HW_TMPDIR}/blockdevices.json"

jq -n \
  --arg hostname    "$(hostname)" \
  --arg kernel      "$(uname -a)" \
  --arg mac         "${MAC}" \
  --arg ip          "${IPADDR}" \
  --slurpfile network        "${HW_TMPDIR}/network.json" \
  --slurpfile blockdevices   "${HW_TMPDIR}/blockdevices.json" \
  --rawfile   lspci          "${HW_TMPDIR}/lspci.txt" \
  --rawfile   lsusb          "${HW_TMPDIR}/lsusb.txt" \
  --rawfile   dmidecode      "${HW_TMPDIR}/dmidecode.txt" \
  --rawfile   nvme           "${HW_TMPDIR}/nvme.txt" \
  --rawfile   ipmi_fru       "${HW_TMPDIR}/ipmi_fru.txt" \
  --rawfile   mdstat         "${HW_TMPDIR}/mdstat.txt" \
  --rawfile   smart          "${HW_TMPDIR}/smart.txt" \
  '{
    hostname:     $hostname,
    kernel:       $kernel,
    primary_mac:  $mac,
    primary_ip:   $ip,
    network:      $network[0],
    blockdevices: $blockdevices[0],
    lspci:        $lspci,
    lsusb:        $lsusb,
    dmidecode:    $dmidecode,
    nvme:         $nvme,
    ipmi_fru:     $ipmi_fru,
    mdstat:       $mdstat,
    smart:        $smart
  }' > "${JSON_OUT}"

chmod 600 "${JSON_OUT}"
ok "Inventory written to ${JSON_OUT}"

##############################################################################
# Cleanup
##############################################################################
rm -rf "${HW_TMPDIR}"
ok "Collection complete - run smbupload.sh to upload inventory"

