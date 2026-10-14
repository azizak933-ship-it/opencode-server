#!/usr/bin/env bash
# Bootstrap the OpenCode server inside a GitHub Codespace (or any container).
#
# There is no systemd in a codespace, so instead of the systemd unit used by
# install.sh this runs the server through OpenCode's own background service -
# which is also the mode that browser, phone and desktop pairing is documented
# against.
#
# Safe to run repeatedly: devcontainer.json calls it on create and on every
# start, so the server comes back whenever the codespace wakes up.
set -euo pipefail

export PATH="$HOME/.opencode/bin:$PATH"
PORT="${OPENCODE_PORT:-49374}"
PASSWORD_FILE="$HOME/.opencode-server-password"
CONFIG_DIR="$HOME/.config/opencode"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# 1. OpenCode ---------------------------------------------------------------
if ! command -v opencode >/dev/null 2>&1; then
  say "installing OpenCode"
  curl -fsSL https://opencode.ai/v2/install | bash
  export PATH="$HOME/.opencode/bin:$PATH"
fi
command -v opencode >/dev/null 2>&1 || { echo "OpenCode install failed" >&2; exit 1; }

# 2. config (projects live under /workspaces in a codespace) ----------------
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/opencode.jsonc" ]; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/opencode.jsonc"
  if [ -f "$SRC" ]; then
    sed 's#/srv/projects#/workspaces#g' "$SRC" > "$CONFIG_DIR/opencode.jsonc"
    say "wrote ${CONFIG_DIR}/opencode.jsonc"
  else
    echo "warn: ${SRC} not found, using OpenCode defaults" >&2
  fi
fi

# 3. server password --------------------------------------------------------
if [ ! -f "$PASSWORD_FILE" ]; then
  (umask 077 && { openssl rand -base64 24 2>/dev/null || head -c 32 /dev/urandom | base64; } | tr -d '\n' > "$PASSWORD_FILE")
fi
PASSWORD="$(cat "$PASSWORD_FILE")"

# 4. server settings --------------------------------------------------------
# hostname 0.0.0.0 is required: port forwarding cannot reach a loopback-only
# listener. Setting any of these stops the service, so they run before start.
opencode service set port "$PORT" >/dev/null
opencode service set password "$PASSWORD" >/dev/null
opencode service set hostname 0.0.0.0 >/dev/null

# 5. start ------------------------------------------------------------------
if opencode service status >/dev/null 2>&1; then
  say "OpenCode is already running"
else
  say "starting OpenCode"
  opencode service start
fi

# 6. what you need to know ---------------------------------------------------
cat <<EOF

OpenCode server is running on port ${PORT}.

  username   opencode
  password   ${PASSWORD}
             (stored at ${PASSWORD_FILE})

Two ways in, both work from any device:

  * Ports tab -> ${PORT} -> open in browser. Use the username and password above.
  * opencode pair --remote   -> prints a link and QR code you can scan with the
                               OpenCode app from anywhere.

Add a model provider: pair a client, then run /connect and /models in it.
Put code to work on in /workspaces.

EOF
