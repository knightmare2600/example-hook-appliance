#!/bin/bash
# /etc/profile.d/spejder-keyboard.sh
# Runs on first login to tty1 - offers keyboard layout selection. Defaults to British (gb) after 10 seconds
# Version history:
# 0.1.0 - Initial - moved from systemd service to profile.d to avoid TTY/HUP issues Only runs on tty1 to
#avoid triggering on SSH sessions

# Only run on tty1, only on first login (check flag file)
[ "$(tty)" = "/dev/tty1" ] || exit 0
[ -f /run/spejder-keyboard-done ] && exit 0
touch /run/spejder-keyboard-done

# Solarized dark - deuteranopes safe
CY="\e[38;5;37m"
GR="\e[38;5;64m"
RS="\e[0m"

TIMEOUT=10

echo
echo -e "${CY}=================================================${RS}"
echo -e "${CY}  Spejder - Keyboard Layout${RS}"
echo -e "${CY}=================================================${RS}"
echo -e "${CY}[keyboard]${RS} Default: British (gb) - accepting in ${TIMEOUT}s"
echo -e "${CY}[keyboard]${RS} Press ENTER to change, or wait to accept"
echo

if read -t ${TIMEOUT} -rp "$(echo -e "${CY}Change keyboard layout? [y/N]:${RS} ")" REPLY; then
  case "${REPLY}" in
    [Yy]*)
      dpkg-reconfigure keyboard-configuration 2>/dev/null && \
      setupcon --force --save-only 2>/dev/null || true
      echo -e "${GR}[keyboard]${RS} Layout updated"
      ;;
  esac
else
  echo
fi

setupcon --force 2>/dev/null || true
