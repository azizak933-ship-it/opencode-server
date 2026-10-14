#!/usr/bin/env bash
# Remove the OpenCode server from this host. Run ON THE SERVER as root:
#
#   sudo bash uninstall.sh            # stop and remove the service + binary
#   sudo bash uninstall.sh --purge    # also delete config, state and user data
#
set -euo pipefail

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

OC_USER="opencode"
OC_HOME="/home/${OC_USER}"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

say "stopping and disabling units"
systemctl disable --now opencode.service opencode-ensure.timer 2>/dev/null || true
systemctl stop opencode.service 2>/dev/null || true

say "removing unit files"
rm -f /etc/systemd/system/opencode.service \
      /etc/systemd/system/opencode-ensure.service \
      /etc/systemd/system/opencode-ensure.timer
systemctl daemon-reload

say "removing launcher"
rm -f /usr/local/bin/opencode

if [ "$PURGE" = 1 ]; then
  say "purging config, state and data"
  rm -rf "${OC_HOME}/.opencode" \
         "${OC_HOME}/.config/opencode" \
         "${OC_HOME}/.local/share/opencode" \
         "${OC_HOME}/.local/state/opencode" \
         /etc/opencode
  if id "$OC_USER" >/dev/null 2>&1; then
    say "removing service user"
    userdel -r "$OC_USER" 2>/dev/null || userdel "$OC_USER" 2>/dev/null || true
  fi
  cat <<EOF

Purged. Anything in your projects directory was left alone - remove it
yourself if you want it gone.
EOF
else
  cat <<EOF

Removed the service and launcher. Kept:

  ${OC_HOME}/.config/opencode         config (including the server password)
  ${OC_HOME}/.local/share/opencode    sessions, database, logs
  ${OC_HOME}/.local/state/opencode    service registration
  ${OC_HOME}/.opencode                the installed binary

Re-run install.sh to bring it back, or 'bash uninstall.sh --purge' to erase
everything. Session data and configuration are never removed by
'opencode uninstall' either.
EOF
fi
