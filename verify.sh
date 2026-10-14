#!/usr/bin/env bash
# Health check for the OpenCode server. Run ON THE SERVER as root:
#
#   sudo bash verify.sh
#
set -euo pipefail

OC_USER="opencode"
OC="/usr/local/bin/opencode"
as_user() { su - "$OC_USER" -c "$1"; }

echo "== unit"
systemctl --no-pager status opencode.service 2>&1 | head -n 20 || true

echo
echo "== unit failures"
systemctl --no-pager --failed 2>&1 | head -n 20 || true

echo
echo "== API (/api/info)"
as_user "${OC} api get /api/info" 2>&1 || echo "(API not responding)"

echo
echo "== service status"
as_user "${OC} service status" 2>&1 || true

echo
echo "== last 20 log lines"
tail -n 20 "/home/${OC_USER}/.local/share/opencode/log/opencode.log" 2>/dev/null \
  || echo "(no log file yet)"
