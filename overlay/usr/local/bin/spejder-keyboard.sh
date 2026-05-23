#!/bin/bash
# spejder-keyboard.sh
# Prompts the user to select a keyboard layout at boot
# Defaults to British (UK) after timeout - if you want something else, speak now
#
# Version history:
# 0.1.0 - Initial version

# Solarized dark palette - deuteranopes (red/green colourblind) safe
CY="\e[38;5;37m"   # Cyan       - information
GR="\e[38;5;64m"   # Green      - success / ok
YL="\e[38;5;136m"  # Yellow     - warning
RS="\e[0m"         # Reset

info()    { echo -e "${CY}[keyboard]${RS} $*"; }
ok()      { echo -e "${GR}[keyboard]${RS} $*"; }
warn()    { echo -e "${YL}[keyboard]${RS} $*"; }

TIMEOUT=10
DEFAULT_LAYOUT="gb"
DEFAULT_MODEL="pc105"
DEFAULT_VARIANT=""
DEFAULT_OPTIONS=""

echo
echo -e "${CY}=================================================${RS}"
echo -e "${CY}  Spejder - Keyboard Layout Selection${RS}"
echo -e "${CY}=================================================${RS}"
echo
info "Default layout: British (gb) - accepting in ${TIMEOUT} seconds"
info "Press ENTER now to change, or wait to accept default"
echo

# Read with timeout
if read -t ${TIMEOUT} -rp "$(echo -e "${CY}Change keyboard layout? [y/N]:${RS} ")" REPLY; then
  case "${REPLY}" in
    [Yy]*)
      echo
      info "Running keyboard configuration..."
      dpkg-reconfigure keyboard-configuration
      setupcon --force --save-only 2>/dev/null || true
      ok "Keyboard layout updated"
      ;;
    *)
      info "Keeping default British layout"
      ;;
  esac
else
  echo
  ok "Timeout reached - using British layout (gb)"
fi

# Apply the layout (default or configured)
setupcon --force 2>/dev/null || localectl set-keymap "${DEFAULT_LAYOUT}" 2>/dev/null || true
ok "Keyboard ready"
